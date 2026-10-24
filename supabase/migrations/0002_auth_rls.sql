-- =====================================================================
-- 0002_auth_rls.sql : helpers, signup trigger, Row Level Security
-- =====================================================================

-- ---------- Helper functions (SECURITY DEFINER to avoid RLS recursion) ----------
create or replace function public.my_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and status = 'active');
$$;

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

-- Raises a user-facing error with a stable code prefix the app can map.
create or replace function public.fail(code text, msg text) returns void
language plpgsql as $$
begin
  raise exception '%', msg using errcode = 'P0001', hint = code;
end $$;

create or replace function public.audit(p_action text, p_entity text, p_entity_id text,
                                        p_before jsonb, p_after jsonb, p_reason text)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_logs (actor_id, action, entity, entity_id, before, after, reason)
  values (auth.uid(), p_action, p_entity, p_entity_id, p_before, p_after, p_reason);
$$;

create or replace function public.check_rate_limit(p_action text, p_max int, p_window_sec int)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.rate_limit_hits
   where user_id = auth.uid() and action = p_action
     and created_at > now() - make_interval(secs => p_window_sec);
  if n >= p_max then
    perform public.fail('RATE_LIMITED', 'Too many requests. Please wait a moment and try again.');
  end if;
  insert into public.rate_limit_hits (user_id, action) values (auth.uid(), p_action);
  delete from public.rate_limit_hits where created_at < now() - interval '1 hour';
end $$;

-- ---------- Signup trigger ----------
-- Role comes from signup metadata but ONLY 'student' or 'driver' are accepted.
-- Admins are promoted manually via promote_to_admin() in the SQL editor.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta     jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role   text  := meta->>'role';
  v_name   text  := trim(coalesce(meta->>'full_name', ''));
  s        public.app_settings;
  v_vs     public.verification_status;
  v_status public.account_status;
  v_cap    int;
  v_term   uuid;
begin
  select * into s from public.app_settings where id;

  if v_role = 'student' then
    if coalesce(meta->>'student_number', '') !~ s.student_number_regex then
      raise exception 'Invalid student number format.' using hint = 'INVALID_STUDENT_NUMBER';
    end if;
    if s.institutional_email_domain is not null
       and lower(new.email) not like '%@' || lower(s.institutional_email_domain) then
      raise exception 'Please use your institutional email address.' using hint = 'INVALID_EMAIL_DOMAIN';
    end if;
    -- Passing a format check is NOT official verification; an admin can mark 'verified'.
    v_vs := 'format_checked';
    v_status := case when s.require_student_admin_approval then 'pending' else 'active' end;

    insert into public.profiles (id, role, full_name, status) values (new.id, 'student', v_name, v_status);
    insert into public.student_profiles (profile_id, student_number, institutional_email, contact_no, verification_status)
    values (new.id, upper(trim(meta->>'student_number')), nullif(trim(meta->>'institutional_email'), ''),
            nullif(trim(meta->>'contact_no'), ''), v_vs);

  elsif v_role = 'driver' then
    v_cap  := nullif(meta->>'capacity', '')::int;
    v_term := nullif(meta->>'terminal_id', '')::uuid;
    if v_cap is null or v_cap < 1 or v_cap > 12 then
      raise exception 'Invalid vehicle capacity.' using hint = 'INVALID_CAPACITY';
    end if;
    if coalesce(meta->>'plate_no', '') = '' or coalesce(meta->>'contact_no', '') = '' then
      raise exception 'Plate number and contact number are required.' using hint = 'MISSING_FIELDS';
    end if;

    -- Drivers ALWAYS start pending; admin approval required before queue access.
    insert into public.profiles (id, role, full_name, status) values (new.id, 'driver', v_name, 'pending');
    insert into public.driver_profiles (profile_id, contact_no, license_no, assigned_terminal_id)
    values (new.id, trim(meta->>'contact_no'), nullif(trim(meta->>'license_no'), ''), v_term);
    insert into public.vehicles (driver_id, plate_no, capacity, status)
    values (new.id, upper(trim(meta->>'plate_no')), v_cap, 'pending');
    insert into public.driver_verification_requests (driver_id) values (new.id);
  else
    -- Allow direct dashboard creations (admins)
    return new;
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- Run manually in the Supabase SQL editor (not callable from the app):
--   select public.promote_to_admin('admin@example.com', 'Terminal Admin');
create or replace function public.promote_to_admin(p_email text, p_name text default 'Administrator')
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then raise exception 'No auth user with that email. Create it first in Auth > Users.'; end if;
  insert into public.profiles (id, role, full_name, status) values (uid, 'admin', p_name, 'active')
  on conflict (id) do update set role = 'admin', status = 'active';
end $$;
revoke all on function public.promote_to_admin(text, text) from public, anon, authenticated;

-- ---------- updated_at triggers ----------
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

create trigger t_profiles_touch  before update on public.profiles  for each row execute function public.touch_updated_at();
create trigger t_vehicles_touch  before update on public.vehicles  for each row execute function public.touch_updated_at();
create trigger t_terminals_touch before update on public.terminals for each row execute function public.touch_updated_at();
create trigger t_tset_touch      before update on public.terminal_settings for each row execute function public.touch_updated_at();
create trigger t_reports_touch   before update on public.feedback_reports  for each row execute function public.touch_updated_at();

-- =====================================================================
-- Row Level Security
-- Principle: clients may READ what they are allowed to see; nearly all
-- WRITES go through SECURITY DEFINER RPCs (0003_queue_rpc.sql).
-- =====================================================================
alter table public.app_settings                 enable row level security;
alter table public.profiles                     enable row level security;
alter table public.student_profiles             enable row level security;
alter table public.driver_profiles              enable row level security;
alter table public.vehicles                     enable row level security;
alter table public.driver_verification_requests enable row level security;
alter table public.terminals                    enable row level security;
alter table public.terminal_settings            enable row level security;
alter table public.terminal_queue_entries       enable row level security;
alter table public.trips                        enable row level security;
alter table public.passenger_count_events       enable row level security;
alter table public.queue_activity               enable row level security;
alter table public.notifications                enable row level security;
alter table public.notification_reads           enable row level security;
alter table public.feedback_reports             enable row level security;
alter table public.audit_logs                   enable row level security;
alter table public.rate_limit_hits              enable row level security;

-- Remove default broad write grants; re-grant narrowly.
revoke insert, update, delete on all tables in schema public from anon, authenticated;
revoke all on all tables in schema public from anon;

-- app_settings: public read (needed by registration form validation)
grant select on public.app_settings to anon, authenticated;
create policy app_settings_read on public.app_settings for select using (true);

-- profiles
create policy profiles_self_read  on public.profiles for select using (id = auth.uid() or public.is_admin());
grant update (full_name) on public.profiles to authenticated;
create policy profiles_self_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- student_profiles
create policy sp_read on public.student_profiles for select using (profile_id = auth.uid() or public.is_admin());
grant update (contact_no, notif_prefs, default_terminal_id, institutional_email) on public.student_profiles to authenticated;
create policy sp_update on public.student_profiles for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- driver_profiles (license is sensitive: self + admin only)
create policy dp_read on public.driver_profiles for select using (profile_id = auth.uid() or public.is_admin());
grant update (contact_no) on public.driver_profiles to authenticated;
create policy dp_update on public.driver_profiles for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- vehicles: owner + admin read; changes via admin RPC only
create policy veh_read on public.vehicles for select using (driver_id = auth.uid() or public.is_admin());

create policy dvr_read on public.driver_verification_requests for select using (driver_id = auth.uid() or public.is_admin());

-- terminals & settings: anyone signed in or not can read basic terminal info (registration needs list)
grant select on public.terminals, public.terminal_settings to anon;
create policy term_read on public.terminals for select using (true);
create policy tset_read on public.terminal_settings for select using (true);

-- queue entries: active signed-in users can read (no personal data in this table).
-- Needed for Realtime change events. Display names/plates come from get_terminal_queue().
create policy tqe_read on public.terminal_queue_entries for select using (public.is_active_user() or driver_id = auth.uid());

create policy trips_read on public.trips for select using (driver_id = auth.uid() or public.is_admin());
create policy pce_read   on public.passenger_count_events for select using (actor_id = auth.uid() or public.is_admin());
create policy qa_read    on public.queue_activity for select using (driver_id = auth.uid() or public.is_admin());

-- notifications: broadcasts for the user's audience + own direct messages
create policy notif_read on public.notifications for select using (
  user_id = auth.uid()
  or public.is_admin()
  or (user_id is null and public.is_active_user() and (
        audience = 'all'
     or (audience = 'students' and public.my_role() = 'student')
     or (audience = 'drivers'  and public.my_role() = 'driver')))
);
grant insert, delete on public.notification_reads to authenticated;
create policy nr_read   on public.notification_reads for select using (user_id = auth.uid());
create policy nr_insert on public.notification_reads for insert with check (user_id = auth.uid());
create policy nr_delete on public.notification_reads for delete using (user_id = auth.uid());

-- feedback: reporter sees own; admins see all; inserts go through submit_report()
create policy fr_read on public.feedback_reports for select using (reporter_id = auth.uid() or public.is_admin());

create policy audit_read on public.audit_logs for select using (public.is_admin());
-- rate_limit_hits: no policies => no client access.

-- ---------- Realtime ----------
alter publication supabase_realtime add table
  public.terminal_queue_entries, public.terminals, public.terminal_settings, public.notifications;
