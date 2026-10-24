-- =====================================================================
-- 0003_queue_rpc.sql : queue state machine & all trusted write paths
--
-- Concurrency model: every queue mutation first locks the TERMINAL row
-- (SELECT ... FOR UPDATE). This serialises all changes per terminal, so
-- simultaneous taps/requests cannot corrupt order or passenger counts.
--
-- Queue rules (confirmed with project owner):
--   * Only the FRONT eligible tricycle accepts passengers (one boarding slot).
--     A tricycle marked 'ready' frees the slot for the next one.
--   * Departure policy per terminal: full | min_threshold | driver_confirmed.
--   * Returning drivers re-enter at the BACK of the queue (new seq).
--   * Resuming from 'paused' re-enters at the BACK (pause = give up place).
--   * Position is derived (ROW_NUMBER by seq) – never client supplied.
-- =====================================================================

-- ---------- Internal helpers ----------
create or replace function public.q_active_statuses() returns public.queue_status[]
language sql immutable as $$ select array['waiting','boarding','almost_full','ready','paused']::public.queue_status[] $$;

create or replace function public.q_boarding_status(p_count int, p_cap int, p_offset int)
returns public.queue_status language sql immutable as $$
  select case when p_count > 0 and p_count >= p_cap - p_offset then 'almost_full'::public.queue_status
              else 'boarding'::public.queue_status end
$$;

create or replace function public.q_policy_satisfied(p_count int, p_cap int, s public.terminal_settings)
returns boolean language sql immutable as $$
  select case s.departure_policy
           when 'full'             then p_count >= p_cap
           when 'min_threshold'    then p_count >= least(s.min_passengers, p_cap)
           when 'driver_confirmed' then p_count >= 1
         end
$$;

create or replace function public.q_needed(p_count int, p_cap int, s public.terminal_settings)
returns int language sql immutable as $$
  select case s.departure_policy
           when 'full'          then greatest(p_cap - p_count, 0)
           when 'min_threshold' then greatest(least(s.min_passengers, p_cap) - p_count, 0)
           else null end   -- driver_confirmed: not calculable
$$;

create or replace function public.q_display_name(p_full text) returns text
language sql immutable as $$
  select case when position(' ' in trim(p_full)) = 0 then trim(p_full)
         else split_part(trim(p_full), ' ', 1) || ' ' ||
              left(regexp_replace(trim(p_full), '^.*\s', ''), 1) || '.' end
$$;

create or replace function public.terminal_is_operating(p_terminal uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare t public.terminals; s public.terminal_settings; loc timestamp; arr jsonb;
begin
  select * into t from public.terminals where id = p_terminal;
  if not found or not t.is_open then return false; end if;
  select * into s from public.terminal_settings where terminal_id = p_terminal;
  if s.operating_hours is null then return true; end if;
  loc := now() at time zone 'Asia/Manila';
  arr := s.operating_hours -> lower(to_char(loc, 'dy'));
  if arr is null or jsonb_array_length(arr) < 2 then return false; end if;
  return loc::time between (arr->>0)::time and (arr->>1)::time;
end $$;

create or replace function public.notify_terminal(p_terminal uuid, p_audience text, p_type text,
                                                  p_title text, p_body text, p_dedupe text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (terminal_id, audience, type, title, body, dedupe_key)
  values (p_terminal, p_audience, p_type, p_title, p_body, p_dedupe)
  on conflict (dedupe_key) do nothing;
$$;

create or replace function public.notify_user(p_user uuid, p_type text, p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, audience, type, title, body)
  values (p_user, 'user', p_type, p_title, p_body);
$$;

create or replace function public.log_activity(p_entry uuid, p_terminal uuid, p_driver uuid, p_action text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.queue_activity (queue_entry_id, terminal_id, driver_id, action, details, actor_id)
  values (p_entry, p_terminal, p_driver, p_action, p_details, auth.uid());
$$;

-- Promote the next waiting tricycle into the boarding slot if it is free.
-- Caller MUST hold the terminal row lock.
create or replace function public.q_recompute(p_terminal uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.terminal_settings; nxt public.terminal_queue_entries; n_active int;
begin
  select * into s from public.terminal_settings where terminal_id = p_terminal;
  if not exists (select 1 from public.terminal_queue_entries
                  where terminal_id = p_terminal and status in ('boarding','almost_full')) then
    select * into nxt from public.terminal_queue_entries
     where terminal_id = p_terminal and status = 'waiting' order by seq limit 1 for update;
    if found then
      update public.terminal_queue_entries
         set status = public.q_boarding_status(passenger_count, capacity_snapshot, s.almost_full_offset),
             boarding_started_at = now(), version = version + 1, updated_at = now()
       where id = nxt.id;
      perform public.log_activity(nxt.id, p_terminal, nxt.driver_id, 'boarding_started', null);
    end if;
  end if;

  select count(*) into n_active from public.terminal_queue_entries
   where terminal_id = p_terminal and status in ('waiting','boarding','almost_full','ready');
  if n_active >= s.long_queue_threshold then
    perform public.notify_terminal(p_terminal, 'all', 'queue_change', 'Long queue at terminal',
      n_active || ' tricycles are currently in the queue.',
      'lq:' || p_terminal || ':' || to_char(now() at time zone 'Asia/Manila', 'YYYYMMDDHH24'));
  end if;
end $$;

-- Returns the caller's active driver context or raises.
create or replace function public.q_require_driver() returns public.driver_profiles
language plpgsql security definer set search_path = public as $$
declare p public.profiles; d public.driver_profiles;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found or p.role <> 'driver' then perform public.fail('NOT_DRIVER', 'Driver account required.'); end if;
  if p.status <> 'active' then
    perform public.fail('DRIVER_NOT_ACTIVE', 'Your driver account is not active (status: ' || p.status || ').');
  end if;
  select * into d from public.driver_profiles where profile_id = p.id;
  return d;
end $$;

-- Locks terminal then the caller's active entry. Returns entry (or raises).
create or replace function public.q_lock_my_entry() returns public.terminal_queue_entries
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries;
begin
  perform public.q_require_driver();
  select * into e from public.terminal_queue_entries
   where driver_id = auth.uid() and status = any (public.q_active_statuses()) limit 1;
  if not found then perform public.fail('NOT_IN_QUEUE', 'You are not currently in a queue.'); end if;
  perform 1 from public.terminals where id = e.terminal_id for update;
  -- Re-read under lock (state may have changed while waiting for the lock).
  select * into e from public.terminal_queue_entries where id = e.id for update;
  if not (e.status = any (public.q_active_statuses())) then
    perform public.fail('NOT_IN_QUEUE', 'Your queue entry is no longer active.');
  end if;
  return e;
end $$;

-- =====================================================================
-- Driver RPCs
-- =====================================================================
create or replace function public.driver_join_queue() returns uuid
language plpgsql security definer set search_path = public as $$
declare d public.driver_profiles; v public.vehicles; t public.terminals; new_id uuid;
begin
  d := public.q_require_driver();
  perform public.check_rate_limit('join', 5, 60);
  if d.assigned_terminal_id is null then
    perform public.fail('NO_TERMINAL', 'You have no assigned terminal. Please contact the administrator.');
  end if;
  select * into t from public.terminals where id = d.assigned_terminal_id for update;
  if not public.terminal_is_operating(t.id) then
    perform public.fail('TERMINAL_CLOSED', 'The terminal is currently closed or outside operating hours.');
  end if;
  select * into v from public.vehicles where driver_id = d.profile_id and status = 'active' order by created_at limit 1;
  if not found then perform public.fail('NO_VEHICLE', 'No approved active vehicle on your account.'); end if;
  if exists (select 1 from public.terminal_queue_entries
              where vehicle_id = v.id and status = any (public.q_active_statuses())) then
    perform public.fail('ALREADY_IN_QUEUE', 'This tricycle is already in a queue.');
  end if;
  if exists (select 1 from public.trips where driver_id = d.profile_id and returned_at is null) then
    perform public.fail('NOT_RETURNED', 'Please mark "Arrived back at terminal" first.');
  end if;

  insert into public.terminal_queue_entries (terminal_id, vehicle_id, driver_id, capacity_snapshot)
  values (t.id, v.id, d.profile_id, v.capacity) returning id into new_id;
  perform public.log_activity(new_id, t.id, d.profile_id, 'joined_queue', jsonb_build_object('plate', v.plate_no));
  perform public.q_recompute(t.id);
  return new_id;
end $$;

create or replace function public.driver_arrived_back() returns uuid
language plpgsql security definer set search_path = public as $$
declare d public.driver_profiles; tr public.trips;
begin
  d := public.q_require_driver();
  select * into tr from public.trips where driver_id = d.profile_id and returned_at is null
   order by departed_at desc limit 1 for update;
  if not found then perform public.fail('NO_OPEN_TRIP', 'No departed trip awaiting return.'); end if;
  update public.trips set returned_at = now() where id = tr.id;
  perform public.log_activity(tr.queue_entry_id, tr.terminal_id, d.profile_id, 'arrived_back', null);
  -- Auto re-join (back of queue) only when the terminal is operating; otherwise
  -- the return is still recorded and the driver can join later.
  if d.assigned_terminal_id is not null and public.terminal_is_operating(d.assigned_terminal_id) then
    return public.driver_join_queue();
  end if;
  return null;
end $$;

-- p_delta must be +1 or -1. p_expected_version (optional) rejects stale taps.
create or replace function public.driver_passenger_delta(p_delta int, p_expected_version int default null)
returns public.terminal_queue_entries
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries; s public.terminal_settings; new_count int; new_status public.queue_status;
begin
  if p_delta not in (1, -1) then perform public.fail('BAD_DELTA', 'Invalid passenger change.'); end if;
  perform public.check_rate_limit('pax', 30, 10);
  e := public.q_lock_my_entry();
  if p_expected_version is not null and p_expected_version <> e.version then
    perform public.fail('STALE', 'Your screen was out of date. It has been refreshed – please try again.');
  end if;
  select * into s from public.terminal_settings where terminal_id = e.terminal_id;

  if p_delta = 1 and e.status not in ('boarding','almost_full') then
    perform public.fail('NOT_BOARDING', 'You can only add passengers while your tricycle is accepting passengers.');
  end if;
  if p_delta = -1 and e.status not in ('boarding','almost_full','ready') then
    perform public.fail('INVALID_STATE', 'Passengers cannot be removed in the current status.');
  end if;
  new_count := e.passenger_count + p_delta;
  if new_count < 0 then perform public.fail('NEGATIVE', 'Passenger count cannot be negative.'); end if;
  if new_count > e.capacity_snapshot then perform public.fail('OVER_CAPACITY', 'Vehicle is already at full capacity.'); end if;

  new_status := e.status;
  if e.status in ('boarding','almost_full') then
    new_status := public.q_boarding_status(new_count, e.capacity_snapshot, s.almost_full_offset);
  elsif e.status = 'ready' and not public.q_policy_satisfied(new_count, e.capacity_snapshot, s) then
    -- No longer meets departure rule: back to accepting passengers.
    new_status := public.q_boarding_status(new_count, e.capacity_snapshot, s.almost_full_offset);
  end if;

  update public.terminal_queue_entries
     set passenger_count = new_count, status = new_status,
         ready_at = case when new_status = 'ready' then ready_at else null end,
         version = version + 1, updated_at = now()
   where id = e.id returning * into e;

  insert into public.passenger_count_events (queue_entry_id, delta, new_count, actor_id)
  values (e.id, p_delta, new_count, auth.uid());

  if new_status = 'almost_full' then
    perform public.notify_terminal(e.terminal_id, 'students', 'almost_full', 'Tricycle almost full',
      'A tricycle has ' || (e.capacity_snapshot - new_count) || ' seat(s) left.', 'af:' || e.id);
  end if;
  return e;
end $$;

create or replace function public.driver_mark_ready() returns public.terminal_queue_entries
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries; s public.terminal_settings;
begin
  e := public.q_lock_my_entry();
  select * into s from public.terminal_settings where terminal_id = e.terminal_id;
  if e.status not in ('boarding','almost_full') then
    perform public.fail('INVALID_STATE', 'Only a tricycle accepting passengers can be marked ready.');
  end if;
  if not public.q_policy_satisfied(e.passenger_count, e.capacity_snapshot, s) then
    perform public.fail('POLICY_NOT_MET', 'Departure requirement not met yet (' ||
      coalesce(public.q_needed(e.passenger_count, e.capacity_snapshot, s)::text, 'more') || ' more passenger(s) needed).');
  end if;
  update public.terminal_queue_entries set status = 'ready', ready_at = now(), version = version + 1, updated_at = now()
   where id = e.id returning * into e;
  perform public.log_activity(e.id, e.terminal_id, e.driver_id, 'marked_ready', jsonb_build_object('passengers', e.passenger_count));
  perform public.notify_terminal(e.terminal_id, 'students', 'ready', 'Tricycle ready to depart',
    'A tricycle is ready to depart. The next tricycle is now accepting passengers.', 'rd:' || e.id);
  perform public.q_recompute(e.terminal_id);
  return e;
end $$;

create or replace function public.driver_unready() returns public.terminal_queue_entries
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries; s public.terminal_settings;
begin
  e := public.q_lock_my_entry();
  if e.status <> 'ready' then perform public.fail('INVALID_STATE', 'Tricycle is not marked ready.'); end if;
  select * into s from public.terminal_settings where terminal_id = e.terminal_id;
  update public.terminal_queue_entries
     set status = public.q_boarding_status(passenger_count, capacity_snapshot, s.almost_full_offset),
         ready_at = null, version = version + 1, updated_at = now()
   where id = e.id returning * into e;
  perform public.log_activity(e.id, e.terminal_id, e.driver_id, 'unmarked_ready', null);
  return e;
end $$;

create or replace function public.driver_confirm_departure() returns public.trips
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries; s public.terminal_settings; tr public.trips;
begin
  e := public.q_lock_my_entry();
  select * into s from public.terminal_settings where terminal_id = e.terminal_id;
  if e.status <> 'ready' then
    perform public.fail('INVALID_STATE', 'Mark the tricycle as "Ready to depart" before confirming departure.');
  end if;
  if not public.q_policy_satisfied(e.passenger_count, e.capacity_snapshot, s) then
    perform public.fail('POLICY_NOT_MET', 'Departure requirement is no longer met.');
  end if;
  update public.terminal_queue_entries
     set status = 'departed', ended_at = now(), end_reason = 'departed', version = version + 1, updated_at = now()
   where id = e.id returning * into e;
  insert into public.trips (queue_entry_id, terminal_id, driver_id, vehicle_id, passenger_count, wait_seconds)
  values (e.id, e.terminal_id, e.driver_id, e.vehicle_id, e.passenger_count,
          extract(epoch from (now() - e.joined_at))::int)
  returning * into tr;   -- UNIQUE(queue_entry_id) blocks duplicate departures
  perform public.log_activity(e.id, e.terminal_id, e.driver_id, 'departed', jsonb_build_object('passengers', e.passenger_count));
  perform public.notify_terminal(e.terminal_id, 'students', 'departed', 'Tricycle departed',
    'A tricycle with ' || e.passenger_count || ' passenger(s) has departed.', 'dp:' || e.id);
  perform public.q_recompute(e.terminal_id);
  return tr;
end $$;

create or replace function public.driver_pause() returns public.terminal_queue_entries
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries;
begin
  e := public.q_lock_my_entry();
  if e.status not in ('waiting','boarding','almost_full') then
    perform public.fail('INVALID_STATE', 'You cannot pause in the current status.');
  end if;
  if e.passenger_count > 0 then
    perform public.fail('HAS_PASSENGERS', 'Remove all passengers before pausing.');
  end if;
  update public.terminal_queue_entries set status = 'paused', boarding_started_at = null, version = version + 1, updated_at = now()
   where id = e.id returning * into e;
  perform public.log_activity(e.id, e.terminal_id, e.driver_id, 'paused', null);
  perform public.q_recompute(e.terminal_id);
  return e;
end $$;

create or replace function public.driver_resume() returns public.terminal_queue_entries
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries;
begin
  e := public.q_lock_my_entry();
  if e.status <> 'paused' then perform public.fail('INVALID_STATE', 'You are not paused.'); end if;
  if not public.terminal_is_operating(e.terminal_id) then
    perform public.fail('TERMINAL_CLOSED', 'The terminal is currently closed.');
  end if;
  -- Re-enter at the back of the queue.
  update public.terminal_queue_entries
     set status = 'waiting', seq = nextval('public.queue_seq'), version = version + 1, updated_at = now()
   where id = e.id returning * into e;
  perform public.log_activity(e.id, e.terminal_id, e.driver_id, 'resumed', null);
  perform public.q_recompute(e.terminal_id);
  return e;
end $$;

-- Vehicle problem / temporary unavailability: leaves the queue.
create or replace function public.driver_leave_queue(p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries;
begin
  if coalesce(trim(p_reason), '') = '' then perform public.fail('REASON_REQUIRED', 'Please provide a reason.'); end if;
  e := public.q_lock_my_entry();
  update public.terminal_queue_entries
     set status = 'removed', ended_at = now(), end_reason = left(trim(p_reason), 300),
         version = version + 1, updated_at = now()
   where id = e.id;
  perform public.log_activity(e.id, e.terminal_id, e.driver_id, 'left_queue',
    jsonb_build_object('reason', left(trim(p_reason), 300), 'passengers', e.passenger_count));
  perform public.notify_terminal(e.terminal_id, 'students', 'queue_change', 'Tricycle left the queue',
    'A tricycle is temporarily unavailable and was removed from the queue.', 'rm:' || e.id);
  perform public.q_recompute(e.terminal_id);
end $$;

create or replace function public.get_driver_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; d public.driver_profiles; v public.vehicles; t public.terminals;
        s public.terminal_settings; e public.terminal_queue_entries; pos int; tr public.trips; req public.driver_verification_requests;
begin
  select * into p from public.profiles where id = auth.uid() and role = 'driver';
  if not found then perform public.fail('NOT_DRIVER', 'Driver account required.'); end if;
  select * into d from public.driver_profiles where profile_id = p.id;
  select * into v from public.vehicles where driver_id = p.id order by created_at limit 1;
  select * into t from public.terminals where id = d.assigned_terminal_id;
  select * into s from public.terminal_settings where terminal_id = d.assigned_terminal_id;
  select * into req from public.driver_verification_requests where driver_id = p.id order by created_at desc limit 1;
  select * into e from public.terminal_queue_entries
   where driver_id = p.id and status = any (public.q_active_statuses()) limit 1;
  if e.id is not null and e.status <> 'paused' then
    select count(*) + 1 into pos from public.terminal_queue_entries
     where terminal_id = e.terminal_id and status in ('waiting','boarding','almost_full','ready') and seq < e.seq;
  end if;
  select * into tr from public.trips where driver_id = p.id and returned_at is null order by departed_at desc limit 1;

  return jsonb_build_object(
    'profile', jsonb_build_object('id', p.id, 'full_name', p.full_name, 'status', p.status, 'status_reason', p.status_reason),
    'driver', jsonb_build_object('contact_no', d.contact_no, 'license_no', d.license_no),
    'vehicle', case when v.id is null then null else to_jsonb(v) end,
    'terminal', case when t.id is null then null else jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.code, 'location_text', t.location_text,
        'is_open', t.is_open, 'closed_reason', t.closed_reason,
        'is_operating', public.terminal_is_operating(t.id)) end,
    'settings', case when s.terminal_id is null then null else to_jsonb(s) end,
    'verification', case when req.id is null then null else jsonb_build_object('status', req.status, 'notes', req.notes) end,
    'entry', case when e.id is null then null else to_jsonb(e) || jsonb_build_object(
        'position', pos, 'seats_left', e.capacity_snapshot - e.passenger_count,
        'needed', public.q_needed(e.passenger_count, e.capacity_snapshot, s),
        'policy_satisfied', public.q_policy_satisfied(e.passenger_count, e.capacity_snapshot, s)) end,
    'open_trip', case when tr.id is null then null else to_jsonb(tr) end,
    'server_time', now());
end $$;

-- =====================================================================
-- Read RPCs (students, drivers, admins)
-- =====================================================================
create or replace function public.get_terminal_queue(p_terminal uuid)
returns table (entry_id uuid, queue_position int, status public.queue_status, passenger_count int, capacity int,
               seats_left int, needed_to_depart int, driver_display text, plate_no text,
               joined_at timestamptz, updated_at timestamptz, version int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare s public.terminal_settings;
begin
  if not public.is_active_user() then perform public.fail('NOT_ACTIVE', 'Active account required.'); end if;
  select * into s from public.terminal_settings where terminal_id = p_terminal;
  return query
  with active as (
    select e.*, row_number() over (order by e.seq)::int as pos
      from public.terminal_queue_entries e
     where e.terminal_id = p_terminal and e.status in ('waiting','boarding','almost_full','ready')
  ), others as (
    select e.*, null::int as pos from public.terminal_queue_entries e
     where e.terminal_id = p_terminal
       and (e.status = 'paused'
         or (e.status = 'departed' and e.ended_at > now() - interval '30 minutes'))
  ), allrows as (select * from active union all select * from others)
  select a.id, a.pos, a.status, a.passenger_count, a.capacity_snapshot,
         a.capacity_snapshot - a.passenger_count,
         case when a.status in ('departed','paused') then null
              else public.q_needed(a.passenger_count, a.capacity_snapshot, s) end,
         public.q_display_name(p.full_name), v.plate_no, a.joined_at, a.updated_at, a.version
    from allrows a
    join public.profiles p on p.id = a.driver_id
    join public.vehicles v on v.id = a.vehicle_id
   order by (a.pos is null), a.pos, a.ended_at desc nulls last;
end $$;

create or replace function public.get_terminal_overview(p_terminal uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t public.terminals; s public.terminal_settings; n_trips int; avg_int numeric; last_upd timestamptz;
        c_queue int; c_accept int; c_ready int; c_today int;
begin
  if not public.is_active_user() then perform public.fail('NOT_ACTIVE', 'Active account required.'); end if;
  select * into t from public.terminals where id = p_terminal;
  if not found then perform public.fail('NOT_FOUND', 'Terminal not found.'); end if;
  select * into s from public.terminal_settings where terminal_id = p_terminal;

  select count(*) filter (where status in ('waiting','boarding','almost_full','ready')),
         count(*) filter (where status in ('boarding','almost_full')),
         count(*) filter (where status = 'ready')
    into c_queue, c_accept, c_ready
    from public.terminal_queue_entries where terminal_id = p_terminal;

  select greatest(max(updated_at), t.updated_at) into last_upd
    from public.terminal_queue_entries where terminal_id = p_terminal;

  select count(*) into c_today from public.trips
   where terminal_id = p_terminal
     and (departed_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date;

  -- Estimate: average gap between consecutive departures in the last 3 hours.
  with recent as (
    select departed_at, lag(departed_at) over (order by departed_at) as prev
      from public.trips where terminal_id = p_terminal and departed_at > now() - interval '3 hours')
  select count(*), avg(extract(epoch from departed_at - prev)) into n_trips, avg_int
    from recent where prev is not null;

  return jsonb_build_object(
    'terminal', jsonb_build_object('id', t.id, 'code', t.code, 'name', t.name, 'location_text', t.location_text,
                                   'latitude', t.latitude, 'longitude', t.longitude,
                                   'is_open', t.is_open, 'closed_reason', t.closed_reason),
    'is_operating', public.terminal_is_operating(t.id),
    'settings', to_jsonb(s),
    'in_queue', c_queue, 'accepting', c_accept, 'ready', c_ready, 'departures_today', c_today,
    'avg_departure_interval_sec', case when n_trips >= greatest(s.min_trips_for_estimate - 1, 1) then round(avg_int) else null end,
    'estimate_sample_size', case when n_trips > 0 then n_trips + 1 else (
        select count(*) from public.trips where terminal_id = p_terminal and departed_at > now() - interval '3 hours') end,
    'last_updated', last_upd, 'server_time', now());
end $$;

-- Public terminal list (for registration & QR resolution)
create or replace function public.list_terminals() returns setof public.terminals
language sql stable security definer set search_path = public as $$
  select * from public.terminals order by name;
$$;

-- Pre-signup validation so the user gets a clear message (Auth hides trigger errors).
create or replace function public.check_registration(p_role text, p_student_number text default null,
                                                     p_plate_no text default null, p_email text default null)
returns text language plpgsql stable security definer set search_path = public as $$
declare s public.app_settings;
begin
  select * into s from public.app_settings where id;
  if p_role = 'student' then
    if coalesce(p_student_number, '') !~ s.student_number_regex then return 'Invalid student number format.'; end if;
    if exists (select 1 from public.student_profiles where student_number = upper(trim(p_student_number))) then
      return 'This student number is already registered.'; end if;
    if s.institutional_email_domain is not null
       and lower(coalesce(p_email, '')) not like '%@' || lower(s.institutional_email_domain) then
      return 'Please use your @' || s.institutional_email_domain || ' email address.'; end if;
  elsif p_role = 'driver' then
    if exists (select 1 from public.vehicles where plate_no = upper(trim(coalesce(p_plate_no, '')))) then
      return 'This plate number is already registered.'; end if;
  else
    return 'Invalid role.';
  end if;
  return null;
end $$;

-- =====================================================================
-- Student / shared write RPCs
-- =====================================================================
create or replace function public.submit_report(p_category public.report_category, p_subject text, p_body text,
                                                p_terminal uuid default null, p_entry uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid; drv uuid;
begin
  if not public.is_active_user() then perform public.fail('NOT_ACTIVE', 'Active account required.'); end if;
  perform public.check_rate_limit('report', 5, 600);
  if p_entry is not null then select driver_id into drv from public.terminal_queue_entries where id = p_entry; end if;
  insert into public.feedback_reports (reporter_id, terminal_id, target_driver_id, category, subject, body, is_sensitive)
  values (auth.uid(), p_terminal, drv, p_category, trim(p_subject), trim(p_body),
          p_category in ('safety','incident','lost_found'))
  returning id into rid;
  return rid;
end $$;

-- =====================================================================
-- Admin RPCs (every one checks is_admin() and writes audit_logs)
-- =====================================================================
create or replace function public.q_require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then perform public.fail('NOT_ADMIN', 'Administrator access required.'); end if;
end $$;

create or replace function public.admin_list_users(p_role public.user_role, p_search text default null)
returns table (id uuid, full_name text, email text, status public.account_status, status_reason text,
               created_at timestamptz, details jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.q_require_admin();
  return query
  select p.id, p.full_name, u.email::text, p.status, p.status_reason, p.created_at,
         case p.role
           when 'student' then (select to_jsonb(sp) from public.student_profiles sp where sp.profile_id = p.id)
           when 'driver'  then (select to_jsonb(dp) || jsonb_build_object(
                                   'vehicle', (select to_jsonb(v) from public.vehicles v where v.driver_id = p.id order by v.created_at limit 1),
                                   'terminal_name', (select tm.name from public.terminals tm where tm.id = dp.assigned_terminal_id),
                                   'request', (select to_jsonb(r) from public.driver_verification_requests r
                                                where r.driver_id = p.id order by r.created_at desc limit 1))
                               from public.driver_profiles dp where dp.profile_id = p.id)
           else '{}'::jsonb end
    from public.profiles p join auth.users u on u.id = p.id
   where p.role = p_role
     and (p_search is null or p_search = ''
          or p.full_name ilike '%' || p_search || '%' or u.email ilike '%' || p_search || '%'
          or exists (select 1 from public.student_profiles sp where sp.profile_id = p.id and sp.student_number ilike '%' || p_search || '%')
          or exists (select 1 from public.vehicles v where v.driver_id = p.id and v.plate_no ilike '%' || p_search || '%'))
   order by p.created_at desc
   limit 500;
end $$;

create or replace function public.admin_review_driver(p_driver uuid, p_approve boolean, p_notes text default null,
                                                      p_terminal uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare before_p jsonb;
begin
  perform public.q_require_admin();
  select to_jsonb(p) into before_p from public.profiles p where id = p_driver and role = 'driver';
  if before_p is null then perform public.fail('NOT_FOUND', 'Driver not found.'); end if;
  if p_approve and p_terminal is null
     and (select assigned_terminal_id from public.driver_profiles where profile_id = p_driver) is null then
    perform public.fail('NO_TERMINAL', 'Assign a terminal before approving.');
  end if;
  if p_terminal is not null then
    update public.driver_profiles set assigned_terminal_id = p_terminal where profile_id = p_driver;
  end if;
  update public.profiles set status = case when p_approve then 'active' else 'rejected' end::public.account_status,
         status_reason = p_notes where id = p_driver;
  update public.vehicles set status = case when p_approve then 'active' else 'rejected' end::public.account_status
   where driver_id = p_driver and status = 'pending';
  update public.driver_verification_requests
     set status = case when p_approve then 'approved' else 'rejected' end::public.request_status,
         notes = p_notes, reviewed_by = auth.uid(), reviewed_at = now()
   where driver_id = p_driver and status = 'pending';
  perform public.audit(case when p_approve then 'driver_approved' else 'driver_rejected' end, 'profiles',
                       p_driver::text, before_p, (select to_jsonb(p) from public.profiles p where id = p_driver), p_notes);
  perform public.notify_user(p_driver, 'account',
    case when p_approve then 'Driver account approved' else 'Driver registration rejected' end,
    coalesce(p_notes, case when p_approve then 'You can now join your assigned terminal queue.' else 'Please contact the administrator.' end));
end $$;

create or replace function public.admin_set_account_status(p_user uuid, p_status public.account_status, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare before_p jsonb; e public.terminal_queue_entries;
begin
  perform public.q_require_admin();
  if coalesce(trim(p_reason), '') = '' then perform public.fail('REASON_REQUIRED', 'A reason is required.'); end if;
  if p_user = auth.uid() then perform public.fail('SELF', 'You cannot change your own account status.'); end if;
  select to_jsonb(p) into before_p from public.profiles p where id = p_user;
  if before_p is null then perform public.fail('NOT_FOUND', 'User not found.'); end if;
  update public.profiles set status = p_status, status_reason = p_reason where id = p_user;
  -- Suspending a driver removes them from any active queue.
  if p_status = 'suspended' then
    for e in select * from public.terminal_queue_entries where driver_id = p_user and status = any (public.q_active_statuses()) loop
      perform 1 from public.terminals where id = e.terminal_id for update;
      update public.terminal_queue_entries set status = 'removed', ended_at = now(), end_reason = 'driver suspended',
             version = version + 1, updated_at = now() where id = e.id;
      perform public.q_recompute(e.terminal_id);
    end loop;
  end if;
  perform public.audit('account_status_changed', 'profiles', p_user::text, before_p,
                       (select to_jsonb(p) from public.profiles p where id = p_user), p_reason);
end $$;

create or replace function public.admin_set_student_verification(p_student uuid, p_status public.verification_status, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  perform public.q_require_admin();
  select to_jsonb(s) into b from public.student_profiles s where profile_id = p_student;
  if b is null then perform public.fail('NOT_FOUND', 'Student not found.'); end if;
  update public.student_profiles set verification_status = p_status where profile_id = p_student;
  if p_status = 'verified' then
    update public.profiles set status = 'active' where id = p_student and status = 'pending';
  end if;
  perform public.audit('student_verification', 'student_profiles', p_student::text, b,
                       (select to_jsonb(s) from public.student_profiles s where profile_id = p_student), p_reason);
end $$;

create or replace function public.admin_update_vehicle(p_vehicle uuid, p_capacity int, p_status public.account_status, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare b public.vehicles;
begin
  perform public.q_require_admin();
  if coalesce(trim(p_reason), '') = '' then perform public.fail('REASON_REQUIRED', 'A reason is required.'); end if;
  select * into b from public.vehicles where id = p_vehicle for update;
  if not found then perform public.fail('NOT_FOUND', 'Vehicle not found.'); end if;
  if p_capacity <> b.capacity and exists (select 1 from public.terminal_queue_entries
       where vehicle_id = p_vehicle and status = any (public.q_active_statuses())) then
    perform public.fail('IN_QUEUE', 'Capacity cannot change while the vehicle is in a queue.');
  end if;
  update public.vehicles set capacity = p_capacity, status = p_status where id = p_vehicle;
  perform public.audit('vehicle_updated', 'vehicles', p_vehicle::text, to_jsonb(b),
                       (select to_jsonb(v) from public.vehicles v where id = p_vehicle), p_reason);
end $$;

create or replace function public.admin_assign_terminal(p_driver uuid, p_terminal uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  perform public.q_require_admin();
  select to_jsonb(d) into b from public.driver_profiles d where profile_id = p_driver;
  if b is null then perform public.fail('NOT_FOUND', 'Driver not found.'); end if;
  if exists (select 1 from public.terminal_queue_entries where driver_id = p_driver and status = any (public.q_active_statuses())) then
    perform public.fail('IN_QUEUE', 'Driver must leave the current queue first.');
  end if;
  update public.driver_profiles set assigned_terminal_id = p_terminal where profile_id = p_driver;
  perform public.audit('terminal_assigned', 'driver_profiles', p_driver::text, b,
                       (select to_jsonb(d) from public.driver_profiles d where profile_id = p_driver), p_reason);
end $$;

create or replace function public.admin_upsert_terminal(p_id uuid, p_code text, p_name text, p_location text,
                                                        p_lat double precision default null, p_lng double precision default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare b jsonb; tid uuid;
begin
  perform public.q_require_admin();
  if p_id is null then
    insert into public.terminals (code, name, location_text, latitude, longitude)
    values (upper(trim(p_code)), trim(p_name), p_location, p_lat, p_lng) returning id into tid;
    insert into public.terminal_settings (terminal_id) values (tid);
  else
    select to_jsonb(t) into b from public.terminals t where id = p_id;
    update public.terminals set code = upper(trim(p_code)), name = trim(p_name), location_text = p_location,
           latitude = p_lat, longitude = p_lng where id = p_id returning id into tid;
  end if;
  perform public.audit(case when p_id is null then 'terminal_created' else 'terminal_updated' end, 'terminals',
                       tid::text, b, (select to_jsonb(t) from public.terminals t where id = tid), null);
  return tid;
end $$;

create or replace function public.admin_set_terminal_open(p_terminal uuid, p_open boolean, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  perform public.q_require_admin();
  if not p_open and coalesce(trim(p_reason), '') = '' then perform public.fail('REASON_REQUIRED', 'A reason is required.'); end if;
  select to_jsonb(t) into b from public.terminals t where id = p_terminal for update;
  update public.terminals set is_open = p_open, closed_reason = case when p_open then null else p_reason end where id = p_terminal;
  perform public.audit(case when p_open then 'terminal_opened' else 'terminal_closed' end, 'terminals', p_terminal::text,
                       b, (select to_jsonb(t) from public.terminals t where id = p_terminal), p_reason);
  perform public.notify_terminal(p_terminal, 'all', 'terminal_status',
    case when p_open then 'Terminal reopened' else 'Terminal temporarily closed' end,
    coalesce(case when p_open then 'The terminal is accepting tricycles and passengers again.' else p_reason end, ''),
    'ts:' || p_terminal || ':' || extract(epoch from now())::bigint);
end $$;

create or replace function public.admin_update_terminal_settings(
  p_terminal uuid, p_policy public.departure_policy, p_min int, p_offset int, p_hours jsonb,
  p_stale int, p_long int, p_min_trips int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  perform public.q_require_admin();
  perform 1 from public.terminals where id = p_terminal for update;
  select to_jsonb(s) into b from public.terminal_settings s where terminal_id = p_terminal;
  update public.terminal_settings
     set departure_policy = p_policy, min_passengers = p_min, almost_full_offset = p_offset,
         operating_hours = p_hours, stale_after_sec = p_stale, long_queue_threshold = p_long,
         min_trips_for_estimate = p_min_trips
   where terminal_id = p_terminal;
  perform public.audit('terminal_settings_updated', 'terminal_settings', p_terminal::text, b,
                       (select to_jsonb(s) from public.terminal_settings s where terminal_id = p_terminal), p_reason);
end $$;

-- Authorised manual correction of an invalid queue state (always audited).
create or replace function public.admin_correct_entry(p_entry uuid, p_count int, p_status public.queue_status, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare e public.terminal_queue_entries; b jsonb;
begin
  perform public.q_require_admin();
  if coalesce(trim(p_reason), '') = '' then perform public.fail('REASON_REQUIRED', 'A reason is required.'); end if;
  if p_status not in ('waiting','boarding','almost_full','ready','paused','removed') then
    perform public.fail('INVALID_STATE', 'Departures must be confirmed by the driver.');
  end if;
  select * into e from public.terminal_queue_entries where id = p_entry;
  if not found then perform public.fail('NOT_FOUND', 'Queue entry not found.'); end if;
  perform 1 from public.terminals where id = e.terminal_id for update;
  select * into e from public.terminal_queue_entries where id = p_entry for update;
  if not (e.status = any (public.q_active_statuses())) then
    perform public.fail('INVALID_STATE', 'Only active entries can be corrected.');
  end if;
  if p_count < 0 or p_count > e.capacity_snapshot then
    perform public.fail('OVER_CAPACITY', 'Passenger count must be between 0 and ' || e.capacity_snapshot || '.');
  end if;
  b := to_jsonb(e);
  update public.terminal_queue_entries
     set passenger_count = p_count, status = p_status,
         ended_at = case when p_status = 'removed' then now() else null end,
         end_reason = case when p_status = 'removed' then 'admin: ' || p_reason else null end,
         version = version + 1, updated_at = now()
   where id = p_entry;
  if p_count <> e.passenger_count then
    insert into public.passenger_count_events (queue_entry_id, delta, new_count, actor_id, source)
    values (p_entry, p_count - e.passenger_count, p_count, auth.uid(), 'admin');
  end if;
  perform public.log_activity(p_entry, e.terminal_id, e.driver_id, 'admin_correction', jsonb_build_object('reason', p_reason));
  perform public.audit('queue_entry_corrected', 'terminal_queue_entries', p_entry::text, b,
                       (select to_jsonb(x) from public.terminal_queue_entries x where id = p_entry), p_reason);
  perform public.q_recompute(e.terminal_id);
end $$;

create or replace function public.admin_update_report(p_report uuid, p_status public.report_status, p_notes text)
returns void language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  perform public.q_require_admin();
  select to_jsonb(r) into b from public.feedback_reports r where id = p_report;
  if b is null then perform public.fail('NOT_FOUND', 'Report not found.'); end if;
  update public.feedback_reports set status = p_status, admin_notes = p_notes where id = p_report;
  perform public.audit('report_updated', 'feedback_reports', p_report::text, b,
                       (select to_jsonb(r) from public.feedback_reports r where id = p_report), p_notes);
end $$;

create or replace function public.admin_update_app_settings(p_regex text, p_domain text, p_require_approval boolean)
returns void language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  perform public.q_require_admin();
  perform regexp_match('test', p_regex);  -- validates regex syntax
  select to_jsonb(a) into b from public.app_settings a where id;
  update public.app_settings set student_number_regex = p_regex, institutional_email_domain = nullif(trim(p_domain), ''),
         require_student_admin_approval = p_require_approval, updated_at = now() where id;
  perform public.audit('app_settings_updated', 'app_settings', 'global', b,
                       (select to_jsonb(a) from public.app_settings a where id), null);
end $$;

create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform public.q_require_admin();
  select jsonb_build_object(
    'students', (select count(*) from public.profiles where role = 'student'),
    'drivers', (select count(*) from public.profiles where role = 'driver'),
    'pending_drivers', (select count(*) from public.driver_verification_requests where status = 'pending'),
    'active_tricycles', (select count(*) from public.terminal_queue_entries where status = any (public.q_active_statuses())),
    'queue_length', (select count(*) from public.terminal_queue_entries where status in ('waiting','boarding','almost_full','ready')),
    'departures_today', (select count(*) from public.trips
        where (departed_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date),
    'avg_wait_today_sec', (select round(avg(wait_seconds)) from public.trips
        where (departed_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date),
    'open_reports', (select count(*) from public.feedback_reports where status in ('submitted','under_review')),
    'recent_activity', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select a.action, a.created_at, a.details, t.name as terminal, public.q_display_name(p.full_name) as driver
          from public.queue_activity a
          left join public.terminals t on t.id = a.terminal_id
          left join public.profiles p on p.id = a.driver_id
         order by a.created_at desc limit 15) x)
  ) into r;
  return r;
end $$;

-- Reports from actual recorded trips only.
create or replace function public.admin_reports(p_terminal uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform public.q_require_admin();
  with t as (
    select tr.*, (tr.departed_at at time zone 'Asia/Manila') as local_ts
      from public.trips tr
     where (p_terminal is null or tr.terminal_id = p_terminal)
       and (tr.departed_at at time zone 'Asia/Manila')::date between p_from and p_to)
  select jsonb_build_object(
    'total_departures', (select count(*) from t),
    'total_passengers', (select coalesce(sum(passenger_count), 0) from t),
    'avg_wait_sec', (select round(avg(wait_seconds)) from t),
    'avg_passengers', (select round(avg(passenger_count)::numeric, 2) from t),
    'by_day', (select coalesce(jsonb_agg(x order by x.day), '[]'::jsonb) from (
        select local_ts::date as day, count(*) as departures, sum(passenger_count) as passengers,
               round(avg(wait_seconds)) as avg_wait_sec from t group by 1) x),
    'by_hour', (select coalesce(jsonb_agg(x order by x.hour), '[]'::jsonb) from (
        select extract(hour from local_ts)::int as hour, count(*) as departures, sum(passenger_count) as passengers
          from t group by 1) x),
    'by_driver', (select coalesce(jsonb_agg(x order by x.departures desc), '[]'::jsonb) from (
        select public.q_display_name(p.full_name) as driver, v.plate_no, count(*) as departures,
               sum(t.passenger_count) as passengers
          from t join public.profiles p on p.id = t.driver_id join public.vehicles v on v.id = t.vehicle_id
         group by 1, 2 limit 50) x)
  ) into r;
  return r;
end $$;

-- =====================================================================
-- Function privileges: deny by default, grant only client-facing RPCs.
-- =====================================================================
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.my_role(), public.is_admin(), public.is_active_user() to anon, authenticated;
grant execute on function public.list_terminals() to anon, authenticated;
grant execute on function public.check_registration(text, text, text, text) to anon, authenticated;

grant execute on function
  public.get_terminal_queue(uuid), public.get_terminal_overview(uuid), public.terminal_is_operating(uuid),
  public.submit_report(public.report_category, text, text, uuid, uuid),
  public.get_driver_status(), public.driver_join_queue(), public.driver_arrived_back(),
  public.driver_passenger_delta(int, int), public.driver_mark_ready(), public.driver_unready(),
  public.driver_confirm_departure(), public.driver_pause(), public.driver_resume(), public.driver_leave_queue(text),
  public.admin_list_users(public.user_role, text), public.admin_review_driver(uuid, boolean, text, uuid),
  public.admin_set_account_status(uuid, public.account_status, text),
  public.admin_set_student_verification(uuid, public.verification_status, text),
  public.admin_update_vehicle(uuid, int, public.account_status, text),
  public.admin_assign_terminal(uuid, uuid, text),
  public.admin_upsert_terminal(uuid, text, text, text, double precision, double precision),
  public.admin_set_terminal_open(uuid, boolean, text),
  public.admin_update_terminal_settings(uuid, public.departure_policy, int, int, jsonb, int, int, int, text),
  public.admin_correct_entry(uuid, int, public.queue_status, text),
  public.admin_update_report(uuid, public.report_status, text),
  public.admin_update_app_settings(text, text, boolean),
  public.admin_overview(), public.admin_reports(uuid, date, date)
to authenticated;

-- Supabase grants EXECUTE on future functions by default; keep new ones private unless granted.
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
