-- SpotSoon fresh-project bootstrap
--
-- Run once in the SQL Editor of a new Supabase project. Do not run this file
-- against an existing SpotSoon database; use the ordered migrations instead.

begin;

-- Trusted parking-zone configuration --------------------------------------

create table public.parking_zones (
    id text primary key,
    name text not null check (length(btrim(name)) between 1 and 100),
    campus text not null check (campus in ('campus_a', 'campus_b')),
    landmark text not null check (length(btrim(landmark)) between 1 and 160),
    latitude double precision not null check (latitude between -90 and 90),
    longitude double precision not null check (longitude between -180 and 180),
    verification_radius_meters double precision not null
        check (verification_radius_meters between 1 and 2000),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint parking_zones_id_check check (id ~ '^[a-z0-9_]{1,64}$')
);

insert into public.parking_zones (
    id, name, campus, landmark, latitude, longitude,
    verification_radius_meters, is_active
) values
(
    'campus_a_student', 'Campus A Student Car Park', 'campus_a',
    'West of the stadium', 26.164736, 50.543676, 140, true
),
(
    'campus_b_student', 'Campus B Student Car Park', 'campus_b',
    'Beside Building 20', 26.158319, 50.546641, 90, true
);

-- Public feed --------------------------------------------------------------

create table public.parking_signals (
    id uuid primary key default gen_random_uuid(),
    created_by uuid not null references auth.users(id) on delete cascade,
    zone_id text references public.parking_zones(id) on update cascade on delete restrict,
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
        check (zone_id is not null and length(btrim(zone)) between 1 and 100),
    constraint parking_signals_status_check check (status in (
        'active', 'claimed', 'arrived', 'vacated',
        'completed', 'unavailable', 'cancelled', 'expired'
    )),
    constraint parking_signals_leaving_after_creation_check
        check (leaving_at > created_at),
    constraint parking_signals_expiration_check
        check (expires_at = leaving_at + interval '5 minutes'),
    constraint parking_signals_claim_state_check check (
        (status in ('claimed', 'arrived', 'vacated')
            and claimed_by is not null and claimed_at is not null)
        or
        (status not in ('claimed', 'arrived', 'vacated')
            and claimed_by is null and claimed_at is null)
    ),
    constraint parking_signals_claimant_is_not_owner_check
        check (claimed_by is null or claimed_by <> created_by),
    constraint parking_signals_claim_time_check check (
        claimed_at is null
        or (claimed_at >= created_at - interval '1 minute' and claimed_at < expires_at)
    )
);

create index parking_signals_visible_leaving_idx
    on public.parking_signals (leaving_at)
    where status in ('active', 'claimed', 'arrived', 'vacated');
create index parking_signals_created_by_idx on public.parking_signals (created_by);
create unique index parking_signals_one_open_per_creator_idx
    on public.parking_signals (created_by)
    where status in ('active', 'claimed', 'arrived', 'vacated');
create index parking_signals_zone_visible_idx
    on public.parking_signals (zone_id, leaving_at)
    where status in ('active', 'claimed', 'arrived', 'vacated');

-- Private saved garage -----------------------------------------------------

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

    constraint vehicles_nickname_check check (length(btrim(nickname)) between 1 and 40),
    constraint vehicles_color_check check (length(btrim(color)) between 1 and 30),
    constraint vehicles_type_check
        check (vehicle_type in ('sedan', 'suv', 'hatchback', 'pickup', 'van', 'other')),
    constraint vehicles_make_check check (make is null or length(btrim(make)) between 1 and 40),
    constraint vehicles_model_check check (model is null or length(btrim(model)) between 1 and 40),
    constraint vehicles_plate_suffix_check
        check (plate_suffix is null or plate_suffix ~ '^[A-Z0-9]{1,3}$')
);

create index vehicles_user_updated_idx on public.vehicles (user_id, updated_at desc);
create unique index vehicles_one_current_per_user_idx
    on public.vehicles (user_id) where is_current;

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

-- Private immutable handover snapshots ------------------------------------

create table public.parking_signal_handovers (
    signal_id uuid primary key references public.parking_signals(id) on delete cascade,
    pass_color text,
    symbol_name text,
    confirmation_number text,
    parking_hint text,
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
        or (pass_color is not null and symbol_name is not null and confirmation_number is not null)
    ),
    constraint handovers_pass_color_check
        check (pass_color is null or pass_color in ('red', 'orange', 'yellow', 'green', 'blue', 'purple')),
    constraint handovers_pass_symbol_check check (
        symbol_name is null or symbol_name in (
            'hare.fill', 'tortoise.fill', 'bird.fill',
            'fish.fill', 'ladybug.fill', 'pawprint.fill'
        )
    ),
    constraint handovers_pass_number_check
        check (confirmation_number is null or confirmation_number ~ '^[0-9]{2}$'),
    constraint handovers_parking_hint_check check (
        parking_hint is null or (
            char_length(parking_hint) between 1 and 120
            and parking_hint = regexp_replace(
                parking_hint, '^[[:space:]]+|[[:space:]]+$', '', 'g'
            )
            and parking_hint !~ '[[:cntrl:]]'
        )
    ),
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
        (claimant_nickname is null and claimant_color is null
            and claimant_vehicle_type is null and claimant_make is null
            and claimant_model is null and claimant_plate_suffix is null
            and pass_color is null)
        or
        (claimant_nickname is not null and claimant_color is not null
            and claimant_vehicle_type is not null and pass_color is not null)
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

-- RLS and client privileges ------------------------------------------------

alter table public.parking_signals enable row level security;
alter table public.parking_zones enable row level security;
alter table public.vehicles enable row level security;
alter table public.parking_signal_handovers enable row level security;

revoke all on table public.parking_signals from anon, authenticated;
revoke all on table public.parking_zones from anon, authenticated;
revoke all on table public.vehicles from anon, authenticated;
revoke all on table public.parking_signal_handovers from anon, authenticated;

grant select on table public.parking_signals to authenticated;
grant select on table public.parking_zones to authenticated;
grant select, delete on table public.vehicles to authenticated;
grant insert (user_id, nickname, color, vehicle_type, make, model, plate_suffix, is_current)
    on table public.vehicles to authenticated;
grant update (nickname, color, vehicle_type, make, model, plate_suffix)
    on table public.vehicles to authenticated;
grant select on table public.parking_signal_handovers to authenticated;

create policy "Authenticated users can read signals"
    on public.parking_signals for select to authenticated using (true);
create policy "Authenticated users can read active parking zones"
    on public.parking_zones for select to authenticated using (is_active);
create policy "Users can read their vehicles"
    on public.vehicles for select to authenticated
    using (user_id = (select auth.uid()));
create policy "Users can insert their vehicles"
    on public.vehicles for insert to authenticated
    with check (user_id = (select auth.uid()) and is_current = false);
create policy "Users can edit their vehicles"
    on public.vehicles for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
create policy "Users can delete their vehicles"
    on public.vehicles for delete to authenticated
    using (user_id = (select auth.uid()));
create policy "Participants can read private handover details"
    on public.parking_signal_handovers for select to authenticated
    using (exists (
        select 1 from public.parking_signals as signal
        where signal.id = parking_signal_handovers.signal_id
          and signal.status in ('active', 'claimed', 'arrived', 'vacated')
          and signal.expires_at > now()
          and (signal.created_by = (select auth.uid())
               or signal.claimed_by = (select auth.uid()))
    ));

-- Garage selection RPC ----------------------------------------------------

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
    select * into v_vehicle from public.vehicles
    where id = p_vehicle_id and user_id = v_user_id for update;
    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
    end if;
    update public.vehicles set is_current = false
    where user_id = v_user_id and is_current and id <> p_vehicle_id;
    update public.vehicles set is_current = true
    where id = p_vehicle_id returning * into v_vehicle;
    return v_vehicle;
end;
$$;

-- Atomic publish and claim RPCs -------------------------------------------

create function public.haversine_distance_meters(
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
            pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_latitude_2 - p_latitude_1) / 2.0), 2)
            + pg_catalog.cos(pg_catalog.radians(p_latitude_1))
            * pg_catalog.cos(pg_catalog.radians(p_latitude_2))
            * pg_catalog.power(pg_catalog.sin(pg_catalog.radians(p_longitude_2 - p_longitude_1) / 2.0), 2)
        )
    );
$$;

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
        v_zone.latitude, v_zone.longitude, p_device_latitude, p_device_longitude
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
        v_signal.id, v_parking_hint, v_vehicle.nickname, v_vehicle.color, v_vehicle.vehicle_type,
        v_vehicle.make, v_vehicle.model, v_vehicle.plate_suffix
    );
    return v_signal;
end;
$$;

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
    select * into v_vehicle from public.vehicles
    where id = p_claimant_vehicle_id and user_id = v_user_id;
    if not found then
        raise exception using errcode = 'P0001', message = 'vehicle_unavailable';
    end if;
    update public.parking_signals
    set status = 'claimed', claimed_by = v_user_id, claimed_at = now()
    where id = p_signal_id and status = 'active' and expires_at > now()
      and created_by <> v_user_id and claimed_by is null and claimed_at is null
    returning * into v_signal;
    if not found then
        raise exception using errcode = 'P0001', message = 'signal_unavailable';
    end if;
    update public.parking_signal_handovers set
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

-- Authorized lifecycle transitions ---------------------------------------

create function public.arrive_at_parking_signal(p_signal_id uuid)
returns public.parking_signals language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_signal public.parking_signals;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    update public.parking_signals set status = 'arrived'
    where id = p_signal_id and status = 'claimed' and claimed_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then raise exception using errcode = 'P0001', message = 'transition_unavailable'; end if;
    return v_signal;
end; $$;

create function public.release_parking_signal(p_signal_id uuid)
returns public.parking_signals language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_signal public.parking_signals;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    update public.parking_signals set status = 'active', claimed_by = null, claimed_at = null
    where id = p_signal_id and status in ('claimed', 'arrived')
      and claimed_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then raise exception using errcode = 'P0001', message = 'transition_unavailable'; end if;
    update public.parking_signal_handovers set
        pass_color = null, symbol_name = null, confirmation_number = null,
        claimant_nickname = null, claimant_color = null, claimant_vehicle_type = null,
        claimant_make = null, claimant_model = null, claimant_plate_suffix = null
    where signal_id = p_signal_id;
    return v_signal;
end; $$;

create function public.cancel_parking_signal(p_signal_id uuid)
returns public.parking_signals language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_signal public.parking_signals;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    update public.parking_signals set status = 'cancelled', claimed_by = null, claimed_at = null
    where id = p_signal_id and status in ('active', 'claimed', 'arrived')
      and created_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then raise exception using errcode = 'P0001', message = 'transition_unavailable'; end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end; $$;

create function public.vacate_parking_signal(p_signal_id uuid)
returns public.parking_signals language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_signal public.parking_signals;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    update public.parking_signals set status = 'vacated'
    where id = p_signal_id and status = 'arrived' and created_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then raise exception using errcode = 'P0001', message = 'transition_unavailable'; end if;
    return v_signal;
end; $$;

create function public.complete_parking_signal(p_signal_id uuid)
returns public.parking_signals language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_signal public.parking_signals;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    update public.parking_signals set status = 'completed', claimed_by = null, claimed_at = null
    where id = p_signal_id and status = 'vacated' and claimed_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then raise exception using errcode = 'P0001', message = 'transition_unavailable'; end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end; $$;

create function public.mark_parking_signal_unavailable(p_signal_id uuid)
returns public.parking_signals language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_signal public.parking_signals;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    update public.parking_signals set status = 'unavailable', claimed_by = null, claimed_at = null
    where id = p_signal_id and status = 'vacated' and claimed_by = v_user_id and expires_at > now()
    returning * into v_signal;
    if not found then raise exception using errcode = 'P0001', message = 'transition_unavailable'; end if;
    delete from public.parking_signal_handovers where signal_id = p_signal_id;
    return v_signal;
end; $$;

create function public.expire_parking_signals()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_count integer;
begin
    if v_user_id is null then raise exception using errcode = '42501', message = 'authentication_required'; end if;
    with expired as (
        update public.parking_signals
        set status = 'expired', claimed_by = null, claimed_at = null
        where status in ('active', 'claimed', 'arrived', 'vacated') and expires_at <= now()
        returning id
    ), removed as (
        delete from public.parking_signal_handovers
        where signal_id in (select id from expired)
    )
    select count(*) into v_count from expired;
    return v_count;
end; $$;

-- RPC execution is available only to authenticated users. ----------------

revoke all on function public.touch_vehicle_updated_at() from public, anon, authenticated, service_role;
revoke all on function public.select_vehicle_after_delete() from public, anon, authenticated, service_role;
revoke all on function public.set_current_vehicle(uuid) from public, anon, service_role;
revoke all on function public.haversine_distance_meters(double precision, double precision, double precision, double precision) from public, anon, authenticated, service_role;
revoke all on function public.publish_parking_signal(text, double precision, double precision, double precision, timestamptz, timestamptz, uuid, text) from public, anon, service_role;
revoke all on function public.claim_parking_signal(uuid, uuid) from public, anon, service_role;
revoke all on function public.arrive_at_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.release_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.cancel_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.vacate_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.complete_parking_signal(uuid) from public, anon, service_role;
revoke all on function public.mark_parking_signal_unavailable(uuid) from public, anon, service_role;
revoke all on function public.expire_parking_signals() from public, anon, service_role;

grant execute on function public.set_current_vehicle(uuid) to authenticated;
grant execute on function public.publish_parking_signal(text, double precision, double precision, double precision, timestamptz, timestamptz, uuid, text) to authenticated;
grant execute on function public.claim_parking_signal(uuid, uuid) to authenticated;
grant execute on function public.arrive_at_parking_signal(uuid) to authenticated;
grant execute on function public.release_parking_signal(uuid) to authenticated;
grant execute on function public.cancel_parking_signal(uuid) to authenticated;
grant execute on function public.vacate_parking_signal(uuid) to authenticated;
grant execute on function public.complete_parking_signal(uuid) to authenticated;
grant execute on function public.mark_parking_signal_unavailable(uuid) to authenticated;
grant execute on function public.expire_parking_signals() to authenticated;

-- Push notification devices and private delivery outbox -------------------

create table public.push_device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null,
    token text not null check (token ~ '^[0-9a-f]{64,256}$'),
    environment text not null check (environment in ('sandbox', 'production')),
    is_active boolean not null default true,
    last_seen_at timestamptz not null default now(),
    invalidated_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, device_id, environment),
    unique (token, environment)
);

create index push_device_tokens_active_user_idx
    on public.push_device_tokens (user_id) where is_active;

alter table public.push_device_tokens enable row level security;
revoke all on table public.push_device_tokens from public, anon, authenticated;
grant select, insert, update, delete on table public.push_device_tokens to authenticated;

create policy "Users can read their push devices"
    on public.push_device_tokens for select to authenticated
    using (user_id = (select auth.uid()));
create policy "Users can add their push devices"
    on public.push_device_tokens for insert to authenticated
    with check (user_id = (select auth.uid()));
create policy "Users can update their push devices"
    on public.push_device_tokens for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
create policy "Users can remove their push devices"
    on public.push_device_tokens for delete to authenticated
    using (user_id = (select auth.uid()));

create function public.register_push_device(
    p_token text,
    p_device_id uuid,
    p_environment text
)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid(); v_token text := lower(btrim(p_token));
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;
    if p_device_id is null or p_environment not in ('sandbox', 'production')
       or v_token !~ '^[0-9a-f]{64,256}$' then
        raise exception using errcode = '22023', message = 'push_device_registration_rejected';
    end if;

    -- Token possession proves this app installation. Rotation or an anonymous
    -- account reset removes the stale association before the new upsert.
    delete from public.push_device_tokens
    where token = v_token and environment = p_environment
      and (user_id <> v_user_id or device_id <> p_device_id);

    insert into public.push_device_tokens (
        user_id, device_id, token, environment, is_active,
        last_seen_at, invalidated_at, updated_at
    ) values (
        v_user_id, p_device_id, v_token, p_environment, true,
        now(), null, now()
    )
    on conflict (user_id, device_id, environment) do update set
        token = excluded.token,
        is_active = true,
        last_seen_at = now(),
        invalidated_at = null,
        updated_at = now();
end; $$;

create function public.deactivate_push_device(p_device_id uuid, p_environment text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user_id uuid := auth.uid();
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;
    update public.push_device_tokens set
        is_active = false, invalidated_at = now(), updated_at = now()
    where user_id = v_user_id and device_id = p_device_id
      and environment = p_environment;
end; $$;

-- This server-only outbox has RLS enabled and no client policy or grant.
create table public.push_notification_events (
    id uuid primary key default gen_random_uuid(),
    signal_id uuid not null references public.parking_signals(id) on delete cascade,
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    event_type text not null check (event_type in (
        'signal_claimed', 'claimant_arrived', 'signal_vacated',
        'claim_released', 'signal_unavailable', 'active_claim_expired'
    )),
    title text not null check (char_length(title) between 1 and 80),
    body text not null check (char_length(body) between 1 and 180),
    transition_key text not null,
    delivery_status text not null default 'pending'
        check (delivery_status in ('pending', 'processing', 'sent', 'failed')),
    attempt_count integer not null default 0 check (attempt_count between 0 and 20),
    next_attempt_at timestamptz not null default now(),
    processing_started_at timestamptz,
    last_error text,
    created_at timestamptz not null default now(),
    sent_at timestamptz,
    unique (signal_id, recipient_user_id, event_type, transition_key)
);

create index push_notification_events_pending_idx
    on public.push_notification_events (next_attempt_at, created_at)
    where delivery_status in ('pending', 'failed');

alter table public.push_notification_events enable row level security;
revoke all on table public.push_notification_events from public, anon, authenticated;

create function public.claim_push_notification_events(p_limit integer default 25)
returns setof public.push_notification_events
language sql security definer set search_path = '' as $$
    with candidates as (
        select id from public.push_notification_events
        where attempt_count < 20
          and next_attempt_at <= now()
          and (
              delivery_status in ('pending', 'failed')
              or (delivery_status = 'processing' and processing_started_at < now() - interval '5 minutes')
          )
        order by created_at
        for update skip locked
        limit greatest(1, least(p_limit, 100))
    )
    update public.push_notification_events as event set
        delivery_status = 'processing',
        processing_started_at = now(),
        attempt_count = event.attempt_count + 1
    from candidates where event.id = candidates.id
    returning event.*;
$$;

create function public.enqueue_parking_signal_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    v_key text := coalesce(new.claimed_at, old.claimed_at, old.created_at)::text;
    v_event text; v_title text; v_body text; v_recipient uuid;
begin
    if old.status = new.status and old.claimed_by is not distinct from new.claimed_by then
        return new;
    end if;

    if old.status = 'active' and new.status = 'claimed' and new.claimed_by is not null then
        v_event := 'signal_claimed'; v_recipient := new.created_by;
        v_title := 'Driver found';
        v_body := 'Someone claimed your parking space and is heading over.';
    elsif old.status = 'claimed' and new.status = 'arrived' then
        v_event := 'claimant_arrived'; v_recipient := new.created_by;
        v_title := 'Driver has arrived';
        v_body := 'The incoming driver is waiting at your parking space.';
    elsif old.status = 'arrived' and new.status = 'vacated' and old.claimed_by is not null then
        v_event := 'signal_vacated'; v_recipient := old.claimed_by;
        v_title := 'Space is vacant';
        v_body := 'The driver has left. The parking space is ready.';
    elsif old.status in ('claimed', 'arrived') and new.status = 'active'
          and old.claimed_by is not null and new.claimed_by is null then
        v_event := 'claim_released'; v_recipient := new.created_by;
        v_title := 'Claim released';
        v_body := 'The incoming driver released the space. Your signal is available again.';
    elsif new.status = 'cancelled' and old.claimed_by is not null then
        v_event := 'signal_unavailable'; v_recipient := old.claimed_by;
        v_title := 'Space unavailable';
        v_body := 'This parking handover is no longer available.';
    elsif new.status = 'unavailable' and old.claimed_by is not null
          and auth.uid() = new.created_by then
        -- Future-safe if an owner-unavailable transition is added. The current
        -- lifecycle lets the claimant report unavailable and must not notify
        -- that same user about their own action.
        v_event := 'signal_unavailable'; v_recipient := old.claimed_by;
        v_title := 'Space unavailable';
        v_body := 'This parking handover is no longer available.';
    end if;

    if v_event is not null and v_recipient is not null then
        insert into public.push_notification_events (
            signal_id, recipient_user_id, event_type, title, body, transition_key
        ) values (new.id, v_recipient, v_event, v_title, v_body, v_key)
        on conflict do nothing;
    end if;

    if new.status = 'expired' and old.status in ('claimed', 'arrived', 'vacated')
       and old.claimed_by is not null then
        insert into public.push_notification_events (
            signal_id, recipient_user_id, event_type, title, body, transition_key
        ) values
            (new.id, new.created_by, 'active_claim_expired', 'Handover expired',
             'This parking handover has expired. Open SpotSoon to refresh.', v_key),
            (new.id, old.claimed_by, 'active_claim_expired', 'Handover expired',
             'This parking handover has expired. Open SpotSoon to refresh.', v_key)
        on conflict do nothing;
    end if;
    return new;
end; $$;

create trigger parking_signals_enqueue_notifications
    after update of status, claimed_by, claimed_at on public.parking_signals
    for each row execute function public.enqueue_parking_signal_notifications();

revoke all on function public.register_push_device(text, uuid, text) from public, anon, service_role;
revoke all on function public.deactivate_push_device(uuid, text) from public, anon, service_role;
revoke all on function public.enqueue_parking_signal_notifications() from public, anon, authenticated, service_role;
revoke all on function public.claim_push_notification_events(integer) from public, anon, authenticated;
grant execute on function public.register_push_device(text, uuid, text) to authenticated;
grant execute on function public.deactivate_push_device(uuid, text) to authenticated;
grant execute on function public.claim_push_notification_events(integer) to service_role;

-- Only public lifecycle rows are broadcast. Static zone definitions, saved
-- vehicles, and private handover snapshots stay out of Realtime.
alter publication supabase_realtime add table public.parking_signals;

commit;

-- The service-role key bypasses RLS. Keep it in trusted server environments;
-- SpotSoon uses only the project URL and publishable client key.
