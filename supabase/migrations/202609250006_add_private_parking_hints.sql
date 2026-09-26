-- Persist an optional parking-location hint with the existing private handover
-- snapshot. Apply manually after 202609250005_repair_zone_and_expiry_api_access.sql.

begin;

alter table public.parking_signal_handovers
    add column parking_hint text;

alter table public.parking_signal_handovers
    add constraint handovers_parking_hint_check check (
        parking_hint is null or (
            char_length(parking_hint) between 1 and 120
            and parking_hint = regexp_replace(
                parking_hint, '^[[:space:]]+|[[:space:]]+$', '', 'g'
            )
            and parking_hint !~ '[[:cntrl:]]'
        )
    );

-- Replace the old seven-argument overload so PostgREST exposes one
-- unambiguous publish RPC signature.
drop function public.publish_parking_signal(
    text, double precision, double precision, double precision,
    timestamptz, timestamptz, uuid
);

create function public.publish_parking_signal(
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

    return v_signal;
end;
$$;

revoke all on function public.publish_parking_signal(
    text, double precision, double precision, double precision,
    timestamptz, timestamptz, uuid, text
) from public, anon, service_role;
grant execute on function public.publish_parking_signal(
    text, double precision, double precision, double precision,
    timestamptz, timestamptz, uuid, text
) to authenticated;

commit;

-- Refresh PostgREST's function signature cache after the overload change.
notify pgrst, 'reload schema';
