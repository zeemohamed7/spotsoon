-- Complete SpotSoon parking handover lifecycle.
-- Apply manually after the atomic-claiming schema from 2026-09-22.

begin;

-- Existing claimed rows predate vehicle details and cannot have a valid private
-- pass. Return unexpired rows to the feed and close expired rows.
update public.parking_signals
set
    status = case when expires_at > now() then 'active' else 'expired' end,
    claimed_by = null,
    claimed_at = null
where status = 'claimed';

-- Earlier development schemas did not all use the same names for these
-- checks. Remove the checks by what they protect so an older constraint does
-- not continue rejecting the new arrived/vacated states.
do $$
declare
    v_constraint record;
begin
    for v_constraint in
        select constraint_name.conname
        from pg_catalog.pg_constraint as constraint_name
        where constraint_name.conrelid = 'public.parking_signals'::regclass
          and constraint_name.contype = 'c'
          and pg_catalog.pg_get_constraintdef(constraint_name.oid) ilike '%status%'
    loop
        execute format(
            'alter table public.parking_signals drop constraint %I',
            v_constraint.conname
        );
    end loop;
end;
$$;

alter table public.parking_signals
    add constraint parking_signals_status_check
        check (status in (
            'active', 'claimed', 'arrived', 'vacated',
            'completed', 'unavailable', 'cancelled', 'expired'
        )),
    add constraint parking_signals_claim_state_check
        check (
            (
                status in ('claimed', 'arrived', 'vacated')
                and claimed_by is not null
                and claimed_at is not null
            )
            or
            (
                status not in ('claimed', 'arrived', 'vacated')
                and claimed_by is null
                and claimed_at is null
            )
        );

drop index if exists public.parking_signals_visible_leaving_idx;
create index parking_signals_visible_leaving_idx
    on public.parking_signals (leaving_at)
    where status in ('active', 'claimed', 'arrived', 'vacated');

-- All lifecycle mutations now go through authenticated RPC functions.
revoke update, delete on table public.parking_signals from authenticated;
revoke update (status) on table public.parking_signals from authenticated;
drop policy if exists "Owners can update their unclaimed signals" on public.parking_signals;
drop policy if exists "Owners can delete their signals" on public.parking_signals;

-- Private handover data -----------------------------------------------------

create table public.parking_signal_handovers (
    signal_id uuid primary key
        references public.parking_signals(id) on delete cascade,
    pass_color text not null,
    symbol_name text not null,
    confirmation_number text not null,
    vehicle_color text not null,
    vehicle_type text not null,
    plate_last_three text,
    created_at timestamptz not null default now(),

    constraint parking_signal_handovers_color_check
        check (pass_color in ('red', 'orange', 'yellow', 'green', 'blue', 'purple')),
    constraint parking_signal_handovers_symbol_check
        check (symbol_name in (
            'hare.fill', 'tortoise.fill', 'bird.fill',
            'fish.fill', 'ladybug.fill', 'pawprint.fill'
        )),
    constraint parking_signal_handovers_number_check
        check (confirmation_number ~ '^[0-9]{2}$'),
    constraint parking_signal_handovers_vehicle_color_check
        check (length(btrim(vehicle_color)) between 1 and 30),
    constraint parking_signal_handovers_vehicle_type_check
        check (vehicle_type in ('car', 'suv', 'pickup', 'motorcycle', 'van')),
    constraint parking_signal_handovers_plate_check
        check (plate_last_three is null or plate_last_three ~ '^[A-Z0-9]{1,3}$')
);

alter table public.parking_signal_handovers enable row level security;
revoke all on table public.parking_signal_handovers from anon, authenticated;
grant select on table public.parking_signal_handovers to authenticated;

create policy "Participants can read private handover details"
    on public.parking_signal_handovers
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.parking_signals as signal
            where signal.id = parking_signal_handovers.signal_id
              and signal.status in ('claimed', 'arrived', 'vacated')
              and signal.expires_at > now()
              and (
                  signal.created_by = (select auth.uid())
                  or signal.claimed_by = (select auth.uid())
              )
        )
    );

-- Atomic lifecycle functions ----------------------------------------------

drop function if exists public.claim_parking_signal(uuid);

create function public.claim_parking_signal(
    p_signal_id uuid,
    p_vehicle_color text,
    p_vehicle_type text,
    p_plate_last_three text default null
)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
    v_plate text := nullif(upper(btrim(p_plate_last_three)), '');
    v_colors text[] := array['red', 'orange', 'yellow', 'green', 'blue', 'purple'];
    v_symbols text[] := array[
        'hare.fill', 'tortoise.fill', 'bird.fill',
        'fish.fill', 'ladybug.fill', 'pawprint.fill'
    ];
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    if p_vehicle_color is null or p_vehicle_type is null
       or length(btrim(p_vehicle_color)) not between 1 and 30
       or lower(p_vehicle_type) not in ('car', 'suv', 'pickup', 'motorcycle', 'van')
       or (v_plate is not null and v_plate !~ '^[A-Z0-9]{1,3}$') then
        raise exception using errcode = '22023', message = 'invalid_vehicle_details';
    end if;

    update public.parking_signals
    set status = 'claimed', claimed_by = v_user_id, claimed_at = now()
    where id = p_signal_id
      and status = 'active'
      and expires_at > now()
      and created_by <> v_user_id
      and claimed_by is null
      and claimed_at is null
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'signal_unavailable';
    end if;

    insert into public.parking_signal_handovers (
        signal_id, pass_color, symbol_name, confirmation_number,
        vehicle_color, vehicle_type, plate_last_three
    ) values (
        v_signal.id,
        v_colors[1 + floor(random() * array_length(v_colors, 1))::integer],
        v_symbols[1 + floor(random() * array_length(v_symbols, 1))::integer],
        lpad(floor(random() * 100)::integer::text, 2, '0'),
        btrim(p_vehicle_color), lower(p_vehicle_type), v_plate
    );

    return v_signal;
end;
$$;

create function public.arrive_at_parking_signal(p_signal_id uuid)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'arrived'
    where id = p_signal_id
      and status = 'claimed'
      and claimed_by = v_user_id
      and expires_at > now()
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    return v_signal;
end;
$$;

create function public.release_parking_signal(p_signal_id uuid)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'active', claimed_by = null, claimed_at = null
    where id = p_signal_id
      and status in ('claimed', 'arrived')
      and claimed_by = v_user_id
      and expires_at > now()
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end;
$$;

create function public.cancel_parking_signal(p_signal_id uuid)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'cancelled', claimed_by = null, claimed_at = null
    where id = p_signal_id
      and status in ('active', 'claimed', 'arrived')
      and created_by = v_user_id
      and expires_at > now()
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end;
$$;

create function public.vacate_parking_signal(p_signal_id uuid)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'vacated'
    where id = p_signal_id
      and status = 'arrived'
      and created_by = v_user_id
      and expires_at > now()
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    return v_signal;
end;
$$;

create function public.complete_parking_signal(p_signal_id uuid)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'completed', claimed_by = null, claimed_at = null
    where id = p_signal_id
      and status = 'vacated'
      and claimed_by = v_user_id
      and expires_at > now()
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end;
$$;

create function public.mark_parking_signal_unavailable(p_signal_id uuid)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'unavailable', claimed_by = null, claimed_at = null
    where id = p_signal_id
      and status = 'vacated'
      and claimed_by = v_user_id
      and expires_at > now()
    returning * into v_signal;

    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end;
$$;

-- Functions are executable only by signed-in users. The service-role key is
-- never needed by SpotSoon and must never be placed in client configuration.
revoke all on function public.claim_parking_signal(uuid, text, text, text) from public, anon, service_role;
revoke all on function public.arrive_at_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.release_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.cancel_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.vacate_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.complete_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.mark_parking_signal_unavailable(uuid) from public, anon, service_role;

grant execute on function public.claim_parking_signal(uuid, text, text, text) to authenticated;
grant execute on function public.arrive_at_parking_signal(uuid) to authenticated;
grant execute on function public.release_parking_signal(uuid) to authenticated;
grant execute on function public.cancel_parking_signal(uuid) to authenticated;
grant execute on function public.vacate_parking_signal(uuid) to authenticated;
grant execute on function public.complete_parking_signal(uuid) to authenticated;
grant execute on function public.mark_parking_signal_unavailable(uuid) to authenticated;

-- parking_signal_handovers is intentionally absent from supabase_realtime.
-- The public signal UPDATE event prompts authorized participants to refetch;
-- RLS then returns private details only to the creator/current claimant.

commit;
