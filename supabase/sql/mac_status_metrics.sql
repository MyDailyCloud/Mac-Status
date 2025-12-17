create extension if not exists "uuid-ossp";

create table if not exists public.mac_status_metrics (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  user_id text,
  device_id uuid references public.mac_status_devices(id),
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

do $$
declare
  device_attnum int;
  exists_fk boolean;
begin
  select attnum
    into device_attnum
    from pg_attribute
   where attrelid = 'public.mac_status_metrics'::regclass
     and attname = 'device_id'
     and not attisdropped;

  if device_attnum is null then
    return;
  end if;

  select exists(
    select 1
      from pg_constraint c
     where c.conrelid = 'public.mac_status_metrics'::regclass
       and c.contype = 'f'
       and c.confrelid = 'public.mac_status_devices'::regclass
       and c.conkey = array[device_attnum]
  )
  into exists_fk;

  if not exists_fk then
    alter table public.mac_status_metrics
      add constraint mac_status_metrics_device_id_fkey
      foreign key (device_id) references public.mac_status_devices(id);
  end if;
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_mac_status_metrics_device_id
  on public.mac_status_metrics (device_id);

create index if not exists idx_mac_status_metrics_device_created
  on public.mac_status_metrics (device_id, created_at desc);

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
