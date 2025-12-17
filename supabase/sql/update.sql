-- MacStatus Supabase 一键更新脚本（幂等）
-- 用法：在 Supabase Dashboard -> SQL Editor 粘贴执行
--
-- 注意：OAuth/GitHub Provider、Redirect URLs 等“控制台配置”无法用 SQL 修改，
-- 仍需按 README 在 Supabase 控制台手动设置（Redirect URL: macstatus://auth-callback）。

begin;

create extension if not exists "uuid-ossp";

-- 设备表
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

drop policy if exists "insert_own_devices" on public.mac_status_devices;
drop policy if exists "select_own_devices" on public.mac_status_devices;
drop policy if exists "update_own_devices" on public.mac_status_devices;

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

-- 指标表（核心列 + payload jsonb）
create table if not exists public.mac_status_metrics (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  user_id text not null,
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

-- 兼容旧项目：如果表已存在，补齐缺失列
alter table public.mac_status_metrics add column if not exists cpu_usage double precision;
alter table public.mac_status_metrics add column if not exists memory_usage double precision;
alter table public.mac_status_metrics add column if not exists used_memory_gb double precision;
alter table public.mac_status_metrics add column if not exists total_memory_gb double precision;
alter table public.mac_status_metrics add column if not exists device_id uuid;
alter table public.mac_status_metrics add column if not exists disk_read_mb_s double precision;
alter table public.mac_status_metrics add column if not exists disk_write_mb_s double precision;
alter table public.mac_status_metrics add column if not exists network_download_mb_s double precision;
alter table public.mac_status_metrics add column if not exists network_upload_mb_s double precision;
alter table public.mac_status_metrics add column if not exists payload jsonb not null default '{}'::jsonb;

-- 设备关联（可重复执行）
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

-- 如果 user_id 之前允许为空，这里不强制改 NOT NULL，避免迁移失败；
-- Mac 客户端已确保写入 user_id（来自 JWT sub）。

alter table public.mac_status_metrics enable row level security;

drop policy if exists "insert_own_metrics" on public.mac_status_metrics;
drop policy if exists "select_own_metrics" on public.mac_status_metrics;

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

commit;
