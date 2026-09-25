-- Repair deterministic Today’s Vehicle selection after deleting the current
-- vehicle. Apply manually after 202609240001_add_garage_and_vehicle_snapshots.sql.

begin;

create or replace function public.select_vehicle_after_delete()
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

drop trigger if exists vehicles_select_after_delete on public.vehicles;
create trigger vehicles_select_after_delete
after delete on public.vehicles
for each row execute function public.select_vehicle_after_delete();

revoke all on function public.select_vehicle_after_delete()
    from public, anon, authenticated, service_role;

-- Heal accounts that already have vehicles but no current selection. The
-- partial unique index still guarantees at most one current row per user.
with replacement as (
    select distinct on (vehicle.user_id)
        vehicle.id,
        vehicle.user_id
    from public.vehicles as vehicle
    where not exists (
        select 1
        from public.vehicles as current_vehicle
        where current_vehicle.user_id = vehicle.user_id
          and current_vehicle.is_current
    )
    order by vehicle.user_id, vehicle.updated_at desc, vehicle.id
)
update public.vehicles as vehicle
set is_current = true
from replacement
where vehicle.id = replacement.id;

commit;
