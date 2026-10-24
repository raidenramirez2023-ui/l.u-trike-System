-- =====================================================================
-- LuTrike – Laguna University Tricycle Queue Management
-- 0001_schema.sql : types, tables, constraints, indexes
-- Independent student project. No official LU integration is assumed.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type public.user_role        as enum ('student', 'driver', 'admin');
create type public.account_status   as enum ('pending', 'active', 'suspended', 'rejected');
create type public.verification_status as enum ('unverified', 'format_checked', 'verified', 'rejected');
create type public.queue_status     as enum ('waiting', 'boarding', 'almost_full', 'ready', 'departed', 'paused', 'removed');
create type public.departure_policy as enum ('full', 'min_threshold', 'driver_confirmed');
create type public.report_category  as enum ('feedback', 'count_error', 'queue_concern', 'safety', 'lost_found', 'incident');
create type public.report_status    as enum ('submitted', 'under_review', 'resolved', 'dismissed');
create type public.request_status   as enum ('pending', 'approved', 'rejected');

-- ---------- Global app settings (single row) ----------
create table public.app_settings (
  id                      boolean primary key default true check (id),
  -- Configurable: the official LU student-number format is NOT known/confirmed.
  student_number_regex    text    not null default '^[A-Za-z0-9-]{5,20}$',
  -- Optional institutional email domain, e.g. 'example.edu.ph'. NULL = not enforced.
  institutional_email_domain text,
  -- If true, students start as 'pending' and need admin verification.
  require_student_admin_approval boolean not null default false,
  updated_at              timestamptz not null default now()
);
insert into public.app_settings default values;

-- ---------- Profiles ----------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        public.user_role      not null,
  full_name   text                  not null check (char_length(full_name) between 2 and 120),
  status      public.account_status not null default 'pending',
  status_reason text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.terminals (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code ~ '^[A-Z0-9-]{3,20}$'),  -- used in QR deep links
  name          text not null,
  location_text text,
  latitude      double precision,
  longitude     double precision,
  is_open       boolean not null default true,
  closed_reason text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.terminal_settings (
  terminal_id        uuid primary key references public.terminals (id) on delete cascade,
  departure_policy   public.departure_policy not null default 'min_threshold',
  min_passengers     int  not null default 1 check (min_passengers >= 1),
  almost_full_offset int  not null default 1 check (almost_full_offset >= 0),
  -- {"mon":["06:00","21:00"], ...}; NULL = no hour restriction. Asia/Manila time.
  operating_hours    jsonb,
  stale_after_sec    int  not null default 300 check (stale_after_sec >= 30),
  long_queue_threshold int not null default 10 check (long_queue_threshold >= 1),
  min_trips_for_estimate int not null default 5 check (min_trips_for_estimate >= 2),
  updated_at         timestamptz not null default now()
);

create table public.student_profiles (
  profile_id          uuid primary key references public.profiles (id) on delete cascade,
  student_number      text not null unique,
  institutional_email text,
  contact_no          text,
  verification_status public.verification_status not null default 'unverified',
  notif_prefs         jsonb not null default
    '{"almost_full":true,"ready":true,"departed":false,"queue_change":false,"terminal_status":true}'::jsonb,
  default_terminal_id uuid references public.terminals (id) on delete set null
);

create table public.driver_profiles (
  profile_id           uuid primary key references public.profiles (id) on delete cascade,
  contact_no           text not null,
  license_no           text,                 -- sensitive: self + admin only
  assigned_terminal_id uuid references public.terminals (id) on delete set null
);

create table public.vehicles (
  id         uuid primary key default gen_random_uuid(),
  driver_id  uuid not null references public.driver_profiles (profile_id) on delete cascade,
  plate_no   text not null unique check (char_length(plate_no) between 3 and 15),
  capacity   int  not null check (capacity between 1 and 12),
  status     public.account_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.vehicles (driver_id);

create table public.driver_verification_requests (
  id           uuid primary key default gen_random_uuid(),
  driver_id    uuid not null references public.driver_profiles (profile_id) on delete cascade,
  status       public.request_status not null default 'pending',
  notes        text,
  reviewed_by  uuid references public.profiles (id),
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create unique index one_pending_request_per_driver
  on public.driver_verification_requests (driver_id) where status = 'pending';

-- ---------- Queue (source of truth for passenger count, status, order) ----------
create sequence public.queue_seq;

create table public.terminal_queue_entries (
  id                 uuid primary key default gen_random_uuid(),
  terminal_id        uuid not null references public.terminals (id),
  vehicle_id         uuid not null references public.vehicles (id),
  driver_id          uuid not null references public.driver_profiles (profile_id),
  status             public.queue_status not null default 'waiting',
  passenger_count    int  not null default 0,
  capacity_snapshot  int  not null check (capacity_snapshot between 1 and 12),
  seq                bigint not null default nextval('public.queue_seq'),   -- ordering key (server only)
  joined_at          timestamptz not null default now(),
  boarding_started_at timestamptz,
  ready_at           timestamptz,
  ended_at           timestamptz,
  end_reason         text,
  version            int not null default 1,
  updated_at         timestamptz not null default now(),
  constraint passenger_count_in_range check (passenger_count between 0 and capacity_snapshot)
);

-- Rule 9: one active entry per vehicle (across all terminals).
create unique index one_active_entry_per_vehicle
  on public.terminal_queue_entries (vehicle_id)
  where status in ('waiting', 'boarding', 'almost_full', 'ready', 'paused');
create index on public.terminal_queue_entries (terminal_id, status, seq);
create index on public.terminal_queue_entries (driver_id, joined_at desc);

create table public.trips (
  id              uuid primary key default gen_random_uuid(),
  queue_entry_id  uuid not null unique references public.terminal_queue_entries (id),  -- no duplicate departures
  terminal_id     uuid not null references public.terminals (id),
  driver_id       uuid not null references public.driver_profiles (profile_id),
  vehicle_id      uuid not null references public.vehicles (id),
  passenger_count int  not null,
  wait_seconds    int  not null,           -- joined_at -> departed_at
  departed_at     timestamptz not null default now(),
  returned_at     timestamptz
);
create index on public.trips (terminal_id, departed_at desc);
create index on public.trips (driver_id, departed_at desc);

create table public.passenger_count_events (
  id             bigint generated always as identity primary key,
  queue_entry_id uuid not null references public.terminal_queue_entries (id),
  delta          int  not null,
  new_count      int  not null,
  actor_id       uuid not null references public.profiles (id),
  source         text not null default 'driver',   -- driver | admin
  created_at     timestamptz not null default now()
);
create index on public.passenger_count_events (queue_entry_id);
create index on public.passenger_count_events (actor_id, created_at desc);

-- Driver activity log (joins, departures, returns, pauses, unavailability)
create table public.queue_activity (
  id             bigint generated always as identity primary key,
  queue_entry_id uuid references public.terminal_queue_entries (id),
  terminal_id    uuid references public.terminals (id),
  driver_id      uuid references public.driver_profiles (profile_id),
  action         text not null,
  details        jsonb,
  actor_id       uuid references public.profiles (id),
  created_at     timestamptz not null default now()
);
create index on public.queue_activity (driver_id, created_at desc);
create index on public.queue_activity (terminal_id, created_at desc);

-- ---------- Notifications ----------
create table public.notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid references public.profiles (id) on delete cascade,  -- NULL = terminal broadcast
  terminal_id uuid references public.terminals (id) on delete cascade,
  audience    text not null default 'students' check (audience in ('students', 'drivers', 'all', 'user')),
  type        text not null,
  title       text not null,
  body        text not null,
  dedupe_key  text unique,
  created_at  timestamptz not null default now()
);
create index on public.notifications (terminal_id, created_at desc);
create index on public.notifications (user_id, created_at desc);

create table public.notification_reads (
  notification_id bigint references public.notifications (id) on delete cascade,
  user_id         uuid   references public.profiles (id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (notification_id, user_id)
);

-- ---------- Feedback / reports (admin-moderated, never public by default) ----------
create table public.feedback_reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles (id) on delete cascade,
  terminal_id      uuid references public.terminals (id),
  target_driver_id uuid references public.driver_profiles (profile_id),
  category         public.report_category not null,
  subject          text not null check (char_length(subject) between 3 and 120),
  body             text not null check (char_length(body) between 5 and 2000),
  status           public.report_status not null default 'submitted',
  admin_notes      text,
  is_sensitive     boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index on public.feedback_reports (status, created_at desc);

-- ---------- Audit log ----------
create table public.audit_logs (
  id         bigint generated always as identity primary key,
  actor_id   uuid references public.profiles (id),
  action     text not null,
  entity     text not null,
  entity_id  text,
  before     jsonb,
  after      jsonb,
  reason     text,
  created_at timestamptz not null default now()
);
create index on public.audit_logs (created_at desc);

-- Simple per-user rate-limit ledger
create table public.rate_limit_hits (
  user_id    uuid not null,
  action     text not null,
  created_at timestamptz not null default now()
);
create index on public.rate_limit_hits (user_id, action, created_at desc);
