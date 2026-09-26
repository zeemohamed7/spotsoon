-- Production-structured push notification outbox and per-user APNs devices.
-- Apply manually after 202609250006_add_private_parking_hints.sql.
-- This migration stores no private handover details in notifications.

begin;

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

commit;

-- push_device_tokens and push_notification_events must NOT be added to
-- supabase_realtime. The Edge Function accesses them with the service role.
