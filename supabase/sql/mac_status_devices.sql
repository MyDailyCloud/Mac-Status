create extension if not exists "uuid-ossp";

create table if not exists public.mac_status_devices (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  user_id text not null,
  device_uuid uuid not null,
  device_name text,
  model text,
  os_version text,
  app_version text,
  last_seen_at timestamptz not null default now()
);

create unique index if not exists mac_status_devices_user_device_unique
  on public.mac_status_devices (user_id, device_uuid);

alter table public.mac_status_devices enable row level security;

create policy "insert_own_devices"
on public.mac_status_devices
for insert
to authenticated
with check (auth.uid()::text = user_id);

create policy "select_own_devices"
on public.mac_status_devices
for select
to authenticated
using (auth.uid()::text = user_id);

create policy "update_own_devices"
on public.mac_status_devices
for update
to authenticated
using (auth.uid()::text = user_id)
with check (auth.uid()::text = user_id);

