create extension if not exists "uuid-ossp";

create table if not exists public.mac_status_metrics (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  user_id text,
  cpu_usage double precision,
  memory_usage double precision,
  used_memory_gb double precision,
  total_memory_gb double precision,
  disk_read_mb_s double precision,
  disk_write_mb_s double precision,
  network_download_mb_s double precision,
  network_upload_mb_s double precision,
  payload jsonb not null default '{}'::jsonb
);

alter table public.mac_status_metrics enable row level security;

create policy "insert_own_metrics"
on public.mac_status_metrics
for insert
to authenticated
with check (auth.uid()::text = user_id);

create policy "select_own_metrics"
on public.mac_status_metrics
for select
to authenticated
using (auth.uid()::text = user_id);
