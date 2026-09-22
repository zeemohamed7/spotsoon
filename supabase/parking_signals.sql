-- SpotSoon database bootstrap
--
-- Run this file once in the SQL Editor of a fresh Supabase project. It is a
-- complete schema definition, not a migration for an existing project.
-- Anonymous Auth users receive the `authenticated` Postgres role after they
-- sign in, so the client never needs a service-role key.

begin;

-- Parking signals -----------------------------------------------------------

create table public.parking_signals (
    id uuid primary key default gen_random_uuid(),
    created_by uuid not null references auth.users(id) on delete cascade,
    campus text not null,
    zone text not null,
    leaving_at timestamptz not null,
    expires_at timestamptz not null,
    status text not null default 'active',
    created_at timestamptz not null default now(),
    claimed_by uuid,
    claimed_at timestamptz,

    constraint parking_signals_campus_check
        check (campus in ('campus_a', 'campus_b')),
    constraint parking_signals_zone_check
        check (
            (campus = 'campus_a' and zone in ('A1', 'A2', 'A3'))
            or
            (campus = 'campus_b' and zone in ('B1', 'B2', 'B3'))
        ),
    constraint parking_signals_status_check
        check (status in ('active', 'claimed', 'cancelled', 'expired')),
    constraint parking_signals_leaving_after_creation_check
        check (leaving_at > created_at),
    constraint parking_signals_expiration_check
        check (expires_at = leaving_at + interval '5 minutes'),
    constraint parking_signals_claim_state_check
        check (
            (
                status = 'claimed'
                and claimed_by is not null
                and claimed_at is not null
            )
            or
            (
                status <> 'claimed'
                and claimed_by is null
                and claimed_at is null
            )
        ),
    constraint parking_signals_claimant_is_not_owner_check
        check (claimed_by is null or claimed_by <> created_by),
    constraint parking_signals_claim_time_check
        check (
            claimed_at is null
            or (
                claimed_at >= created_at - interval '1 minute'
                and claimed_at < expires_at
            )
        )
);

-- Supports the app's active/claimed, non-expired, earliest-leaving query.
create index parking_signals_visible_leaving_idx
    on public.parking_signals (leaving_at)
    where status in ('active', 'claimed');

create index parking_signals_created_by_idx
    on public.parking_signals (created_by);

-- Row Level Security and client privileges ---------------------------------

alter table public.parking_signals enable row level security;

revoke all on table public.parking_signals from anon, authenticated;

grant select, insert, delete on table public.parking_signals to authenticated;

-- Owners only need a direct status update for cancellation/expiration.
-- claimed_by and claimed_at deliberately remain unavailable to table updates;
-- only claim_parking_signal may set them.
grant update (status) on table public.parking_signals to authenticated;

create policy "Authenticated users can read signals"
    on public.parking_signals
    for select
    to authenticated
    using (true);

create policy "Users can insert their own active signals"
    on public.parking_signals
    for insert
    to authenticated
    with check (
        created_by = (select auth.uid())
        and status = 'active'
        and claimed_by is null
        and claimed_at is null
        and created_at >= now() - interval '1 minute'
        and created_at <= now() + interval '1 minute'
        and leaving_at > now()
        and leaving_at <= now() + interval '11 minutes'
    );

create policy "Owners can update their unclaimed signals"
    on public.parking_signals
    for update
    to authenticated
    using (created_by = (select auth.uid()))
    with check (
        created_by = (select auth.uid())
        and status in ('active', 'cancelled', 'expired')
        and claimed_by is null
        and claimed_at is null
    );

create policy "Owners can delete their signals"
    on public.parking_signals
    for delete
    to authenticated
    using (created_by = (select auth.uid()));

-- Atomic claiming -----------------------------------------------------------

-- SECURITY DEFINER lets this narrowly scoped function set the claim columns
-- even though clients have no direct UPDATE privilege on those columns. The
-- empty search path and fully qualified names prevent object-shadowing attacks.
create function public.claim_parking_signal(p_signal_id uuid)
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
        raise exception using
            errcode = '42501',
            message = 'authentication_required';
    end if;

    -- This single conditional update is atomic. Concurrent callers contend on
    -- the row lock; after one succeeds, every other caller no longer matches
    -- status = 'active' and receives signal_unavailable below.
    update public.parking_signals
    set
        status = 'claimed',
        claimed_by = v_user_id,
        claimed_at = now()
    where id = p_signal_id
      and status = 'active'
      and expires_at > now()
      and created_by <> v_user_id
      and claimed_by is null
      and claimed_at is null
    returning * into v_signal;

    if not found then
        raise exception using
            errcode = 'P0001',
            message = 'signal_unavailable';
    end if;

    return v_signal;
end;
$$;

-- PostgreSQL grants function execution to PUBLIC by default. Remove every
-- client/server role grant, then allow only signed-in users to call this RPC.
revoke all on function public.claim_parking_signal(uuid)
    from public, anon, service_role;
grant execute on function public.claim_parking_signal(uuid)
    to authenticated;

-- Realtime -----------------------------------------------------------------

-- INSERT, UPDATE, and DELETE events are observed by the Swift client. RLS
-- continues to control which authenticated subscribers may receive rows.
alter publication supabase_realtime add table public.parking_signals;

commit;

-- The service-role key bypasses RLS by design. Keep it only in trusted server
-- environments; never place it in SpotSoon configuration or client source.
