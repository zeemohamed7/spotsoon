-- Submission hardening for private push tokens and server-scheduled expiry.
-- Apply manually after 202609250008_add_live_approach_tracking.sql.
-- This migration prepares a scheduler-safe function but does not create a
-- Supabase Cron job.

begin;

-- Device-token registration, rotation, and deactivation must use the
-- authenticated SECURITY DEFINER RPCs from migration 202609250007. Clients may
-- still read their own device rows so Settings/diagnostics can remain possible.
revoke insert, update, delete on table public.push_device_tokens from authenticated;

drop policy if exists "Users can add their push devices" on public.push_device_tokens;
drop policy if exists "Users can update their push devices" on public.push_device_tokens;
drop policy if exists "Users can remove their push devices" on public.push_device_tokens;

revoke all on table public.push_device_tokens from public, anon;
grant select on table public.push_device_tokens to authenticated;

-- The dispatcher uses the service role to read recipient tokens and deactivate
-- rejected APNs tokens. These server-only grants never reach the iOS client.
grant select, update on table public.push_device_tokens to service_role;
grant select, update on table public.push_notification_events to service_role;

-- Supabase Cron runs trusted SQL as the database owner. The service-role grant
-- also permits a trusted server scheduler to invoke the same idempotent cleanup
-- without granting ordinary authenticated clients elevated access.
create function public.expire_parking_signals_scheduled()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_count integer;
begin
    with expired as (
        update public.parking_signals
        set status = 'expired', claimed_by = null, claimed_at = null
        where status in ('active', 'claimed', 'arrived', 'vacated')
          and expires_at <= now()
        returning id
    ), removed_handovers as (
        delete from public.parking_signal_handovers
        where signal_id in (select id from expired)
    )
    select count(*) into v_count from expired;

    -- Migration 202609250008 installs the status trigger that deletes each
    -- expired signal's participant-only parking_signal_locations row. Repeated
    -- calls find no eligible rows and safely return zero.
    return v_count;
end;
$$;

revoke all on function public.expire_parking_signals_scheduled()
    from public, anon, authenticated;
grant execute on function public.expire_parking_signals_scheduled()
    to service_role;

commit;

-- Manual Supabase Cron configuration after this migration:
--   Name: expire-parking-signals
--   Schedule: * * * * *
--   SQL: select public.expire_parking_signals_scheduled();
-- Do not add private token, outbox, handover, or location tables to Realtime.
