-- =====================================================================
-- LuTrike Demo Seed Data (Development and Demonstration Only)
-- IMPORTANT: This script uses sample data to simulate real terminal conditions.
-- It is clearly marked as demo/test data.
-- =====================================================================

-- 1. Create Laguna University Terminals (Gate 1, AV Building, Oval & Rooms)
insert into public.terminals (id, code, name, location_text, latitude, longitude, is_open)
values
  ('11111111-1111-1111-1111-111111111111', 'GATE1', 'Laguna University Gate 1 Terminal', 'Main Gate Entrance, Laguna University, Brgy. Bubukal, Sta. Cruz', 14.2575, 121.4048, true),
  ('22222222-2222-2222-2222-222222222222', 'AVBLDG', 'LU AV Building Terminal', 'Audio-Visual Building / Academic Quadrangle, LU Campus', 14.2568, 121.4055, true),
  ('33333333-3333-3333-3333-333333333333', 'OVAL', 'LU Oval & Rooms Terminal', 'Near Laguna Sports Complex Track Oval & LU Classrooms', 14.2558, 121.4042, true)
on conflict (id) do update set 
  code = excluded.code,
  name = excluded.name,
  location_text = excluded.location_text,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  is_open = excluded.is_open;

-- 2. Terminal Settings (Configured departure policies: 4 passengers per standard tricycle)
insert into public.terminal_settings (terminal_id, departure_policy, min_passengers, almost_full_offset, stale_after_sec)
values
  ('11111111-1111-1111-1111-111111111111', 'min_threshold', 4, 1, 300),
  ('22222222-2222-2222-2222-222222222222', 'min_threshold', 4, 1, 300),
  ('33333333-3333-3333-3333-333333333333', 'min_threshold', 4, 1, 300)
on conflict (terminal_id) do update set departure_policy = excluded.departure_policy;

-- 3. Note on Creating Demo Auth Accounts:
-- In Supabase Auth, users are created either via Auth > Users in the dashboard,
-- or via signup in the app. For convenience, once you sign up with:
--   - student@lu.edu.ph
--   - driver1@lutrike.ph
--   - driver2@lutrike.ph
--   - admin@lutrike.ph
-- You can make admin@lutrike.ph an administrator by running:
--   select public.promote_to_admin('admin@lutrike.ph', 'System Administrator');
