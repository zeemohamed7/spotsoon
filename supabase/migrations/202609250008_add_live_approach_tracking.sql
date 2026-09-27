-- Temporary participant-only live approach tracking.
-- Apply manually after 202609250007_add_push_notifications.sql.
-- Coordinates remain outside parking_signals and the public Realtime feed.

begin;

create table public.parking_signal_locations (
    signal_id uuid primary key references public.parking_signals(id) on delete cascade,
    owner_latitude double precision not null check (owner_latitude between -90 and 90),
    owner_longitude double precision not null check (owner_longitude between -180 and 180),
    owner_horizontal_accuracy double precision not null
        check (owner_horizontal_accuracy between 0 and 65),
    owner_captured_at timestamptz not null,
    claimant_latitude double precision check (claimant_latitude between -90 and 90),
    claimant_longitude double precision check (claimant_longitude between -180 and 180),
    claimant_horizontal_accuracy double precision
        check (claimant_horizontal_accuracy between 0 and 65),
    claimant_captured_at timestamptz,
    claimant_sharing_enabled boolean not null default false,
    updated_at timestamptz not null default now(),
    constraint parking_signal_locations_claimant_state_check check (
        (claimant_latitude is null and claimant_longitude is null
            and claimant_horizontal_accuracy is null and claimant_captured_at is null)
        or
        (claimant_latitude is not null and claimant_longitude is not null
            and claimant_horizontal_accuracy is not null and claimant_captured_at is not null)
    )
);

alter table public.parking_signal_locations enable row level security;
revoke all on table public.parking_signal_locations from public, anon, authenticated;
grant select on table public.parking_signal_locations to authenticated;

create policy "Participants can read temporary approach locations"
    on public.parking_signal_locations for select to authenticated
    using (exists (
        select 1 from public.parking_signals as signal
        where signal.id = parking_signal_locations.signal_id
          and signal.expires_at > now()
          and (
              (signal.created_by = (select auth.uid())
                  and signal.status in ('active', 'claimed', 'arrived', 'vacated'))
              or
              (signal.claimed_by = (select auth.uid())
                  and signal.status in ('claimed', 'arrived', 'vacated'))
          )
    ));

-- Publishing still validates against trusted zone geometry, and now retains the
-- accepted device reading atomically in participant-protected storage.
create or replace function public.publish_parking_signal(
    p_zone_id text,
    p_device_latitude double precision,
    p_device_longitude double precision,
    p_horizontal_accuracy double precision,
    p_leaving_at timestamptz,
    p_expires_at timestamptz,
    p_owner_vehicle_id uuid,
    p_parking_hint text default null
)
returns public.parking_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_zone public.parking_zones;
    v_vehicle public.vehicles;
    v_signal public.parking_signals;
    v_distance double precision;
    v_tolerance double precision;
    v_parking_hint text;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    update public.parking_signals
    set status = 'expired', claimed_by = null, claimed_at = null
    where created_by = v_user_id
      and status in ('active', 'claimed', 'arrived', 'vacated')
      and expires_at <= now();

    delete from public.parking_signal_handovers as handover
    using public.parking_signals as signal
    where handover.signal_id = signal.id
      and signal.created_by = v_user_id
      and signal.status = 'expired';

    if exists (
        select 1 from public.parking_signals
        where created_by = v_user_id
          and status in ('active', 'claimed', 'arrived', 'vacated')
    ) then
        raise exception using errcode = 'P0001', message = 'active_signal_exists';
    end if;

    select * into v_zone from public.parking_zones
    where id = p_zone_id and is_active;
    if not found then
        raise exception using errcode = 'P0001', message = 'zone_unavailable';
    end if;

    select * into v_vehicle from public.vehicles
    where id = p_owner_vehicle_id and user_id = v_user_id;
    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
    end if;

    if p_parking_hint is null or p_parking_hint ~ '^[[:space:]]*$' then
        v_parking_hint := null;
    elsif p_parking_hint ~ '[[:cntrl:]]' then
        raise exception using errcode = '22023', message = 'invalid_parking_hint';
    else
        v_parking_hint := regexp_replace(
            p_parking_hint, '^[[:space:]]+|[[:space:]]+$', '', 'g'
        );
        if char_length(v_parking_hint) > 120 then
            raise exception using errcode = '22023', message = 'invalid_parking_hint';
        end if;
    end if;

    if p_device_latitude is null or p_device_longitude is null
       or p_horizontal_accuracy is null
       or p_device_latitude::text in ('NaN', 'Infinity', '-Infinity')
       or p_device_longitude::text in ('NaN', 'Infinity', '-Infinity')
       or p_horizontal_accuracy::text in ('NaN', 'Infinity', '-Infinity')
       or p_device_latitude not between -90 and 90
       or p_device_longitude not between -180 and 180
       or p_horizontal_accuracy < 0 then
        raise exception using errcode = '22023', message = 'location_unavailable';
    end if;

    if p_horizontal_accuracy > 65 then
        raise exception using errcode = '22023', message = 'location_inaccurate';
    end if;

    v_distance := public.haversine_distance_meters(
        v_zone.latitude, v_zone.longitude,
        p_device_latitude, p_device_longitude
    );
    v_tolerance := least(p_horizontal_accuracy, 25.0);
    if v_distance > v_zone.verification_radius_meters + v_tolerance then
        raise exception using errcode = 'P0001', message = 'outside_parking_zone';
    end if;

    if p_leaving_at <= now()
       or p_leaving_at > now() + interval '11 minutes'
       or p_expires_at <> p_leaving_at + interval '5 minutes' then
        raise exception using errcode = '22023', message = 'invalid_signal_time';
    end if;

    insert into public.parking_signals (
        created_by, zone_id, campus, zone, leaving_at, expires_at, status
    ) values (
        v_user_id, v_zone.id, v_zone.campus, v_zone.name,
        p_leaving_at, p_expires_at, 'active'
    ) returning * into v_signal;

    insert into public.parking_signal_handovers (
        signal_id, parking_hint, owner_nickname, owner_color, owner_vehicle_type,
        owner_make, owner_model, owner_plate_suffix
    ) values (
        v_signal.id, v_parking_hint,
        v_vehicle.nickname, v_vehicle.color, v_vehicle.vehicle_type,
        v_vehicle.make, v_vehicle.model, v_vehicle.plate_suffix
    );

    insert into public.parking_signal_locations (
        signal_id, owner_latitude, owner_longitude, owner_horizontal_accuracy, owner_captured_at
    ) values (
        v_signal.id, p_device_latitude, p_device_longitude, p_horizontal_accuracy, now()
    );

    return v_signal;
end;
$$;

create function public.set_approach_location_sharing(
    p_signal_id uuid, p_enabled boolean
) returns public.parking_signal_locations
language plpgsql security definer set search_path = '' as $$
declare
    v_user_id uuid := auth.uid();
    v_location public.parking_signal_locations;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;
    if p_enabled is null then
        raise exception using errcode = '22023', message = 'invalid_sharing_state';
    end if;
    update public.parking_signal_locations as location set
        claimant_sharing_enabled = p_enabled, updated_at = now()
    from public.parking_signals as signal
    where location.signal_id = p_signal_id
      and signal.id = location.signal_id
      and signal.claimed_by = v_user_id
      and signal.status in ('claimed', 'arrived')
      and signal.expires_at > now()
    returning location.* into v_location;
    if not found then
        raise exception using errcode = 'P0001', message = 'approach_unavailable';
    end if;
    return v_location;
end; $$;

create function public.update_claimant_approach_location(
    p_signal_id uuid,
    p_latitude double precision,
    p_longitude double precision,
    p_horizontal_accuracy double precision,
    p_captured_at timestamptz
) returns public.parking_signal_locations
language plpgsql security definer set search_path = '' as $$
declare
    v_user_id uuid := auth.uid();
    v_location public.parking_signal_locations;
    v_elapsed double precision;
    v_moved double precision;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;
    if p_latitude is null or p_longitude is null or p_horizontal_accuracy is null
       or p_captured_at is null
       or p_latitude::text in ('NaN', 'Infinity', '-Infinity')
       or p_longitude::text in ('NaN', 'Infinity', '-Infinity')
       or p_horizontal_accuracy::text in ('NaN', 'Infinity', '-Infinity')
       or p_latitude not between -90 and 90
       or p_longitude not between -180 and 180
       or p_horizontal_accuracy not between 0 and 65
       or p_captured_at < now() - interval '15 seconds'
       or p_captured_at > now() + interval '5 seconds' then
        raise exception using errcode = '22023', message = 'invalid_approach_location';
    end if;

    select location.* into v_location
    from public.parking_signal_locations as location
    join public.parking_signals as signal on signal.id = location.signal_id
    where location.signal_id = p_signal_id
      and location.claimant_sharing_enabled
      and signal.claimed_by = v_user_id
      and signal.status in ('claimed', 'arrived')
      and signal.expires_at > now()
    for update of location;
    if not found then
        raise exception using errcode = 'P0001', message = 'approach_unavailable';
    end if;

    if v_location.claimant_captured_at is not null then
        if p_captured_at <= v_location.claimant_captured_at then
            return v_location;
        end if;
        v_elapsed := extract(epoch from (p_captured_at - v_location.claimant_captured_at));
        v_moved := public.haversine_distance_meters(
            v_location.claimant_latitude, v_location.claimant_longitude,
            p_latitude, p_longitude
        );
        if v_elapsed < 5 and v_moved < 15 then
            return v_location;
        end if;
    end if;

    update public.parking_signal_locations set
        claimant_latitude = p_latitude,
        claimant_longitude = p_longitude,
        claimant_horizontal_accuracy = p_horizontal_accuracy,
        claimant_captured_at = p_captured_at,
        updated_at = now()
    where signal_id = p_signal_id
    returning * into v_location;
    return v_location;
end; $$;

create function public.clean_parking_signal_locations()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.status in ('completed', 'unavailable', 'cancelled', 'expired') then
        delete from public.parking_signal_locations where signal_id = new.id;
    elsif old.status in ('claimed', 'arrived') and new.status = 'active' then
        update public.parking_signal_locations set
            claimant_latitude = null, claimant_longitude = null,
            claimant_horizontal_accuracy = null, claimant_captured_at = null,
            claimant_sharing_enabled = false, updated_at = now()
        where signal_id = new.id;
    elsif old.status = 'active' and new.status = 'claimed' then
        update public.parking_signal_locations set
            claimant_latitude = null, claimant_longitude = null,
            claimant_horizontal_accuracy = null, claimant_captured_at = null,
            claimant_sharing_enabled = false, updated_at = now()
        where signal_id = new.id;
    elsif new.status = 'vacated' then
        update public.parking_signal_locations set
            claimant_sharing_enabled = false, updated_at = now()
        where signal_id = new.id;
    end if;
    return new;
end; $$;

create trigger parking_signals_clean_private_locations
    after update of status, claimed_by, claimed_at on public.parking_signals
    for each row execute function public.clean_parking_signal_locations();

revoke all on function public.set_approach_location_sharing(uuid, boolean)
    from public, anon, service_role;
revoke all on function public.update_claimant_approach_location(
    uuid, double precision, double precision, double precision, timestamptz
) from public, anon, service_role;
revoke all on function public.clean_parking_signal_locations()
    from public, anon, authenticated, service_role;
grant execute on function public.set_approach_location_sharing(uuid, boolean) to authenticated;
grant execute on function public.update_claimant_approach_location(
    uuid, double precision, double precision, double precision, timestamptz
) to authenticated;

commit;

-- Do not add parking_signal_locations to supabase_realtime. Participant clients
-- poll the RLS-protected row while Live Handover is visible.
