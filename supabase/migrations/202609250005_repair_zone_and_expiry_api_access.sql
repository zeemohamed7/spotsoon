-- Repair the two API objects required by the map feed.
-- Safe to run on an existing project after migration 202609250004.

begin;

alter table public.parking_zones enable row level security;

revoke all on table public.parking_zones from anon, authenticated;
grant select on table public.parking_zones to authenticated;

drop policy if exists "Authenticated users can read active parking zones"
    on public.parking_zones;
create policy "Authenticated users can read active parking zones"
    on public.parking_zones for select to authenticated
    using (is_active);

create or replace function public.expire_parking_signals()
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

revoke all on function public.expire_parking_signals()
    from public, anon, service_role;
grant execute on function public.expire_parking_signals()
    to authenticated;

commit;

-- Ask PostgREST to refresh its function and privilege cache immediately.
notify pgrst, 'reload schema';
