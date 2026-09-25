-- Add My Garage, Today’s Vehicle, and private handover vehicle snapshots.
-- Apply manually after 202609230001_complete_handover_lifecycle.sql.

begin;

-- Private saved vehicles ----------------------------------------------------

create table public.vehicles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    nickname text not null,
    color text not null,
    vehicle_type text not null,
    make text,
    model text,
    plate_suffix text,
    is_current boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint vehicles_nickname_check
        check (length(btrim(nickname)) between 1 and 40),
    constraint vehicles_color_check
        check (length(btrim(color)) between 1 and 30),
    constraint vehicles_type_check
        check (vehicle_type in ('sedan', 'suv', 'hatchback', 'pickup', 'van', 'other')),
    constraint vehicles_make_check
        check (make is null or length(btrim(make)) between 1 and 40),
    constraint vehicles_model_check
        check (model is null or length(btrim(model)) between 1 and 40),
    constraint vehicles_plate_suffix_check
        check (plate_suffix is null or plate_suffix ~ '^[A-Z0-9]{1,3}$')
);

create index vehicles_user_updated_idx
    on public.vehicles (user_id, updated_at desc);

create unique index vehicles_one_current_per_user_idx
    on public.vehicles (user_id)
    where is_current;

create function public.touch_vehicle_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger vehicles_touch_updated_at
before update on public.vehicles
for each row execute function public.touch_vehicle_updated_at();

-- When the current vehicle is deleted, choose the most recently updated
-- remaining vehicle. If none remains, the user deterministically has no
-- current vehicle.
create function public.select_vehicle_after_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_replacement_id uuid;
begin
    if old.is_current then
        perform pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(old.user_id::text, 0)
        );

        select vehicle.id into v_replacement_id
        from public.vehicles as vehicle
        where vehicle.user_id = old.user_id
        order by vehicle.updated_at desc, vehicle.id
        limit 1
        for update;

        update public.vehicles
        set is_current = true
        where id = v_replacement_id;
    end if;
    return old;
end;
$$;

create trigger vehicles_select_after_delete
after delete on public.vehicles
for each row execute function public.select_vehicle_after_delete();

revoke all on function public.touch_vehicle_updated_at()
    from public, anon, authenticated, service_role;
revoke all on function public.select_vehicle_after_delete()
    from public, anon, authenticated, service_role;

alter table public.vehicles enable row level security;
revoke all on table public.vehicles from anon, authenticated;
grant select, delete on table public.vehicles to authenticated;
grant insert (user_id, nickname, color, vehicle_type, make, model, plate_suffix, is_current)
    on table public.vehicles to authenticated;
grant update (nickname, color, vehicle_type, make, model, plate_suffix)
    on table public.vehicles to authenticated;

create policy "Users can read their vehicles"
    on public.vehicles for select to authenticated
    using (user_id = (select auth.uid()));

create policy "Users can insert their vehicles"
    on public.vehicles for insert to authenticated
    with check (
        user_id = (select auth.uid())
        and is_current = false
    );

create policy "Users can edit their vehicles"
    on public.vehicles for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy "Users can delete their vehicles"
    on public.vehicles for delete to authenticated
    using (user_id = (select auth.uid()));

create function public.set_current_vehicle(p_vehicle_id uuid)
returns public.vehicles
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_vehicle public.vehicles;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(v_user_id::text, 0)
    );

    select * into v_vehicle
    from public.vehicles
    where id = p_vehicle_id and user_id = v_user_id
    for update;

    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
    end if;

    update public.vehicles
    set is_current = false
    where user_id = v_user_id and is_current and id <> p_vehicle_id;

    update public.vehicles
    set is_current = true
    where id = p_vehicle_id
    returning * into v_vehicle;

    return v_vehicle;
end;
$$;

revoke all on function public.set_current_vehicle(uuid) from public, anon, service_role;
grant execute on function public.set_current_vehicle(uuid) to authenticated;

-- Replace the first-spike private table with owner and claimant snapshots.
-- Existing in-progress development signals cannot have a trusted owner
-- snapshot, so close them before replacing their private rows.
update public.parking_signals
set
    status = case when expires_at <= now() then 'expired' else 'cancelled' end,
    claimed_by = null,
    claimed_at = null
where status in ('active', 'claimed', 'arrived', 'vacated');

drop table public.parking_signal_handovers;

create table public.parking_signal_handovers (
    signal_id uuid primary key references public.parking_signals(id) on delete cascade,
    pass_color text,
    symbol_name text,
    confirmation_number text,

    owner_nickname text not null,
    owner_color text not null,
    owner_vehicle_type text not null,
    owner_make text,
    owner_model text,
    owner_plate_suffix text,

    claimant_nickname text,
    claimant_color text,
    claimant_vehicle_type text,
    claimant_make text,
    claimant_model text,
    claimant_plate_suffix text,
    created_at timestamptz not null default now(),

    constraint handovers_pass_consistency_check check (
        (pass_color is null and symbol_name is null and confirmation_number is null)
        or
        (pass_color is not null and symbol_name is not null and confirmation_number is not null)
    ),
    constraint handovers_pass_color_check
        check (pass_color is null or pass_color in ('red', 'orange', 'yellow', 'green', 'blue', 'purple')),
    constraint handovers_pass_symbol_check
        check (symbol_name is null or symbol_name in (
            'hare.fill', 'tortoise.fill', 'bird.fill',
            'fish.fill', 'ladybug.fill', 'pawprint.fill'
        )),
    constraint handovers_pass_number_check
        check (confirmation_number is null or confirmation_number ~ '^[0-9]{2}$'),
    constraint handovers_owner_nickname_check
        check (length(btrim(owner_nickname)) between 1 and 40),
    constraint handovers_owner_color_check
        check (length(btrim(owner_color)) between 1 and 30),
    constraint handovers_owner_type_check
        check (owner_vehicle_type in ('sedan', 'suv', 'hatchback', 'pickup', 'van', 'other')),
    constraint handovers_owner_make_check
        check (owner_make is null or length(btrim(owner_make)) between 1 and 40),
    constraint handovers_owner_model_check
        check (owner_model is null or length(btrim(owner_model)) between 1 and 40),
    constraint handovers_owner_plate_check
        check (owner_plate_suffix is null or owner_plate_suffix ~ '^[A-Z0-9]{1,3}$'),
    constraint handovers_claimant_consistency_check check (
        (
            claimant_nickname is null and claimant_color is null
            and claimant_vehicle_type is null and claimant_make is null
            and claimant_model is null and claimant_plate_suffix is null
            and pass_color is null
        )
        or
        (
            claimant_nickname is not null and claimant_color is not null
            and claimant_vehicle_type is not null and pass_color is not null
        )
    ),
    constraint handovers_claimant_nickname_check
        check (claimant_nickname is null or length(btrim(claimant_nickname)) between 1 and 40),
    constraint handovers_claimant_color_check
        check (claimant_color is null or length(btrim(claimant_color)) between 1 and 30),
    constraint handovers_claimant_type_check
        check (claimant_vehicle_type is null or claimant_vehicle_type in ('sedan', 'suv', 'hatchback', 'pickup', 'van', 'other')),
    constraint handovers_claimant_make_check
        check (claimant_make is null or length(btrim(claimant_make)) between 1 and 40),
    constraint handovers_claimant_model_check
        check (claimant_model is null or length(btrim(claimant_model)) between 1 and 40),
    constraint handovers_claimant_plate_check
        check (claimant_plate_suffix is null or claimant_plate_suffix ~ '^[A-Z0-9]{1,3}$')
);

alter table public.parking_signal_handovers enable row level security;
revoke all on table public.parking_signal_handovers from anon, authenticated;
grant select on table public.parking_signal_handovers to authenticated;

create policy "Participants can read private handover details"
    on public.parking_signal_handovers for select to authenticated
    using (
        exists (
            select 1
            from public.parking_signals as signal
            where signal.id = parking_signal_handovers.signal_id
              and signal.status in ('active', 'claimed', 'arrived', 'vacated')
              and signal.expires_at > now()
              and (
                  signal.created_by = (select auth.uid())
                  or signal.claimed_by = (select auth.uid())
              )
        )
    );

-- Publishing and claiming copy only server-read, caller-owned vehicle rows. --

revoke insert on table public.parking_signals from authenticated;
drop policy if exists "Users can insert their own active signals" on public.parking_signals;

create function public.publish_parking_signal(
    p_campus text,
    p_zone text,
    p_leaving_at timestamptz,
    p_expires_at timestamptz,
    p_owner_vehicle_id uuid
)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_vehicle public.vehicles;
    v_signal public.parking_signals;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    if p_leaving_at <= now()
       or p_leaving_at > now() + interval '11 minutes'
       or p_expires_at <> p_leaving_at + interval '5 minutes' then
        raise exception using errcode = '22023', message = 'invalid_signal_time';
    end if;

    select * into v_vehicle
    from public.vehicles
    where id = p_owner_vehicle_id and user_id = v_user_id;
    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
    end if;

    insert into public.parking_signals (
        created_by, campus, zone, leaving_at, expires_at, status
    ) values (
        v_user_id, p_campus, p_zone, p_leaving_at, p_expires_at, 'active'
    ) returning * into v_signal;

    insert into public.parking_signal_handovers (
        signal_id, owner_nickname, owner_color, owner_vehicle_type,
        owner_make, owner_model, owner_plate_suffix
    ) values (
        v_signal.id, v_vehicle.nickname, v_vehicle.color, v_vehicle.vehicle_type,
        v_vehicle.make, v_vehicle.model, v_vehicle.plate_suffix
    );

    return v_signal;
end;
$$;

drop function if exists public.claim_parking_signal(uuid, text, text, text);

create function public.claim_parking_signal(
    p_signal_id uuid,
    p_claimant_vehicle_id uuid
)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_vehicle public.vehicles;
    v_signal public.parking_signals;
    v_colors text[] := array['red', 'orange', 'yellow', 'green', 'blue', 'purple'];
    v_symbols text[] := array[
        'hare.fill', 'tortoise.fill', 'bird.fill',
        'fish.fill', 'ladybug.fill', 'pawprint.fill'
    ];
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    select * into v_vehicle
    from public.vehicles
    where id = p_claimant_vehicle_id and user_id = v_user_id;
    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
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

    update public.parking_signal_handovers
    set
        pass_color = v_colors[1 + floor(random() * array_length(v_colors, 1))::integer],
        symbol_name = v_symbols[1 + floor(random() * array_length(v_symbols, 1))::integer],
        confirmation_number = lpad(floor(random() * 100)::integer::text, 2, '0'),
        claimant_nickname = v_vehicle.nickname,
        claimant_color = v_vehicle.color,
        claimant_vehicle_type = v_vehicle.vehicle_type,
        claimant_make = v_vehicle.make,
        claimant_model = v_vehicle.model,
        claimant_plate_suffix = v_vehicle.plate_suffix
    where signal_id = p_signal_id;
    if not found then
        raise exception using errcode = 'P0001', message = 'private_handover_unavailable';
    end if;

    return v_signal;
end;
$$;

create or replace function public.release_parking_signal(p_signal_id uuid)
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
    where id = p_signal_id and status in ('claimed', 'arrived')
      and claimed_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then
        raise exception using errcode = 'P0001', message = 'transition_unavailable';
    end if;
    update public.parking_signal_handovers
    set
        pass_color = null, symbol_name = null, confirmation_number = null,
        claimant_nickname = null, claimant_color = null,
        claimant_vehicle_type = null, claimant_make = null,
        claimant_model = null, claimant_plate_suffix = null
    where signal_id = p_signal_id;
    return v_signal;
end;
$$;

create function public.expire_parking_signals()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_count integer;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;
    with expired as (
        update public.parking_signals
        set status = 'expired', claimed_by = null, claimed_at = null
        where status in ('active', 'claimed', 'arrived', 'vacated')
          and expires_at <= now()
        returning id
    ), removed as (
        delete from public.parking_signal_handovers
        where signal_id in (select id from expired)
    )
    select count(*) into v_count from expired;
    return v_count;
end;
$$;

revoke all on function public.publish_parking_signal(text, text, timestamptz, timestamptz, uuid)
    from public, anon, service_role;
revoke all on function public.claim_parking_signal(uuid, uuid)
    from public, anon, service_role;
revoke all on function public.expire_parking_signals()
    from public, anon, service_role;

grant execute on function public.publish_parking_signal(text, text, timestamptz, timestamptz, uuid)
    to authenticated;
grant execute on function public.claim_parking_signal(uuid, uuid)
    to authenticated;
grant execute on function public.expire_parking_signals()
    to authenticated;

-- vehicles and parking_signal_handovers remain outside supabase_realtime.
-- Only public parking_signals changes notify clients to refetch private rows
-- through participant-only RLS.

commit;
