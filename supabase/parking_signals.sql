-- Run once in the SQL Editor of a fresh Supabase project.
create table public.parking_signals (
    id uuid primary key default gen_random_uuid(),
    created_by uuid not null references auth.users(id) on delete cascade,
    campus text not null check (campus in ('campus_a', 'campus_b')),
    zone text not null,
    leaving_at timestamptz not null,
    expires_at timestamptz not null,
    status text not null default 'active' check (status in ('active', 'cancelled', 'expired')),
    created_at timestamptz not null default now(),
    check ((campus = 'campus_a' and zone in ('A1', 'A2', 'A3')) or
           (campus = 'campus_b' and zone in ('B1', 'B2', 'B3'))),
    check (expires_at = leaving_at + interval '5 minutes')
);
create index parking_signals_active_leaving on public.parking_signals(leaving_at)
    where status = 'active';
alter table public.parking_signals enable row level security;
revoke all on public.parking_signals from anon, authenticated;
grant select, insert on public.parking_signals to authenticated;
-- Anonymous Auth users assume the authenticated database role.
-- Read access includes inactive rows so UPDATE transitions can reach subscribers.
create policy "Signed-in users can read signals" on public.parking_signals
    for select to authenticated using (true);
create policy "Users can publish their own signals" on public.parking_signals
    for insert to authenticated with check (
        created_by = (select auth.uid()) and status = 'active'
        and leaving_at > now() and leaving_at <= now() + interval '11 minutes'
    );
alter publication supabase_realtime add table public.parking_signals;
