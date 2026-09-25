-- Add the Campus B student car park beside Building 20.
-- Apply manually after 202609250002_add_gps_verified_parking_zone.sql.
-- This deliberately leaves Campus A, RLS, grants, Realtime, signals, and
-- private handover data unchanged.

begin;

insert into public.parking_zones (
    id, name, campus, landmark, latitude, longitude,
    verification_radius_meters, is_active
) values (
    'campus_b_student',
    'Campus B Student Car Park',
    'campus_b',
    'Beside Building 20',
    26.158319,
    50.546641,
    90,
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

commit;
