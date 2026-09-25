-- Add the first trusted parking-zone definition and GPS-verified publishing.
-- Apply manually after 202609250001_repair_current_vehicle_selection.sql.
-- Object creation is restart-safe so a partially selected SQL Editor run can
-- be repaired by running this entire file again.

begin;

create table if not exists public.parking_zones (
    id text primary key,
    name text not null,
    campus text not null,
    landmark text not null,
    latitude double precision not null,
    longitude double precision not null,
    verification_radius_meters double precision not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint parking_zones_id_check check (id ~ '^[a-z0-9_]{1,64}$'),
    constraint parking_zones_name_check check (length(btrim(name)) between 1 and 100),
    constraint parking_zones_campus_check check (campus in ('campus_a', 'campus_b')),
    constraint parking_zones_landmark_check check (length(btrim(landmark)) between 1 and 160),
    constraint parking_zones_latitude_check check (latitude between -90 and 90),
    constraint parking_zones_longitude_check check (longitude between -180 and 180),
    constraint parking_zones_radius_check check (verification_radius_meters between 1 and 2000)
);

insert into public.parking_zones (
    id, name, campus, landmark, latitude, longitude,
    verification_radius_meters, is_active
) values (
    'campus_a_student',
    'Campus A Student Car Park',
    'campus_a',
    'West of the stadium',
    26.164736,
    50.543676,
    140,
    true
)
on conflict (id) do update set
    name = excluded.name,
    campus = excluded.campus,
    landmark = excluded.landmark,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    verification_radius_meters = excluded.verification_radius_meters,
    is_active = excluded.is_active,
    updated_at = now();

alter table public.parking_zones enable row level security;
revoke all on table public.parking_zones from anon, authenticated;
grant select on table public.parking_zones to authenticated;

drop policy if exists "Authenticated users can read active parking zones"
    on public.parking_zones;
create policy "Authenticated users can read active parking zones"
    on public.parking_zones for select to authenticated
    using (is_active);

alter table public.parking_signals
    add column if not exists zone_id text;

do $$
begin
    if not exists (
        select 1
        from pg_catalog.pg_constraint
        where conrelid = 'public.parking_signals'::regclass
          and conname = 'parking_signals_zone_id_fkey'
    ) then
        alter table public.parking_signals
            add constraint parking_signals_zone_id_fkey
            foreign key (zone_id) references public.parking_zones(id)
            on update cascade on delete restrict;
    end if;
end;
$$;

-- Legacy development signals retain their reliable display strings and a
-- null zone_id. New signals always receive a trusted zone association in the
-- publish RPC.
alter table public.parking_signals
    drop constraint if exists parking_signals_zone_check,
    add constraint parking_signals_zone_check check (
        (
            zone_id is null
            and (
                (campus = 'campus_a' and zone in ('A1', 'A2', 'A3'))
                or (campus = 'campus_b' and zone in ('B1', 'B2', 'B3'))
            )
        )
        or (
            zone_id is not null
            and length(btrim(zone)) between 1 and 100
        )
    );

create index if not exists parking_signals_zone_visible_idx
    on public.parking_signals (zone_id, leaving_at)
    where status in ('active', 'claimed', 'arrived', 'vacated');

create or replace function public.haversine_distance_meters(
    p_latitude_1 double precision,
    p_longitude_1 double precision,
    p_latitude_2 double precision,
    p_longitude_2 double precision
)
returns double precision
language sql
immutable
strict
set search_path = ''
as $$
    select 6371000.0 * 2.0 * pg_catalog.asin(
        pg_catalog.sqrt(
            pg_catalog.power(
                pg_catalog.sin(pg_catalog.radians(p_latitude_2 - p_latitude_1) / 2.0),
                2
            )
            + pg_catalog.cos(pg_catalog.radians(p_latitude_1))
            * pg_catalog.cos(pg_catalog.radians(p_latitude_2))
            * pg_catalog.power(
                pg_catalog.sin(pg_catalog.radians(p_longitude_2 - p_longitude_1) / 2.0),
                2
            )
        )
    );
$$;

revoke all on function public.haversine_distance_meters(
    double precision, double precision, double precision, double precision
) from public, anon, authenticated, service_role;

drop function if exists public.publish_parking_signal(text, text, timestamptz, timestamptz, uuid);

create or replace function public.publish_parking_signal(
    p_zone_id text,
    p_device_latitude double precision,
    p_device_longitude double precision,
    p_horizontal_accuracy double precision,
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
    v_zone public.parking_zones;
    v_vehicle public.vehicles;
    v_signal public.parking_signals;
    v_distance double precision;
    v_tolerance double precision;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    select * into v_zone
    from public.parking_zones
    where id = p_zone_id and is_active;
    if not found then
        raise exception using errcode = 'P0001', message = 'zone_unavailable';
    end if;

    select * into v_vehicle
    from public.vehicles
    where id = p_owner_vehicle_id and user_id = v_user_id;
    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
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
        signal_id, owner_nickname, owner_color, owner_vehicle_type,
        owner_make, owner_model, owner_plate_suffix
    ) values (
        v_signal.id, v_vehicle.nickname, v_vehicle.color, v_vehicle.vehicle_type,
        v_vehicle.make, v_vehicle.model, v_vehicle.plate_suffix
    );

    return v_signal;
end;
$$;

revoke all on function public.publish_parking_signal(
    text, double precision, double precision, double precision,
    timestamptz, timestamptz, uuid
) from public, anon, service_role;
grant execute on function public.publish_parking_signal(
    text, double precision, double precision, double precision,
    timestamptz, timestamptz, uuid
) to authenticated;

-- parking_zones is intentionally static configuration, not a Realtime table.
-- Public parking_signals remains the only published table used by this feature.

commit;
