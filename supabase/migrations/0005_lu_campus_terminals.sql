-- =====================================================================
-- Migration 0005: Laguna University Campus Terminals (Brgy. Bubukal, Sta. Cruz)
-- 
-- Registers and updates the 3 actual tricycle terminals at Laguna University:
-- 1. Gate 1 Terminal (Main Gate Entrance)
-- 2. AV Building Terminal (Academic / Audio-Visual Hall)
-- 3. LU Rooms & Oval Terminal (Laguna Sports Complex Track Oval & Rooms)
-- =====================================================================

-- 1. Insert or update the 3 real Laguna University terminals with exact Bubukal GPS coordinates
INSERT INTO public.terminals (id, code, name, location_text, latitude, longitude, is_open)
VALUES
  (
    '11111111-1111-1111-1111-111111111111',
    'GATE1',
    'Laguna University Gate 1 Terminal',
    'Main Gate Entrance, Laguna University, Brgy. Bubukal, Sta. Cruz',
    14.2575,
    121.4048,
    true
  ),
  (
    '22222222-2222-2222-2222-222222222222',
    'AVBLDG',
    'LU AV Building Terminal',
    'Audio-Visual Building / Academic Quadrangle, LU Campus',
    14.2568,
    121.4055,
    true
  ),
  (
    '33333333-3333-3333-3333-333333333333',
    'OVAL',
    'LU Oval & Rooms Terminal',
    'Near Laguna Sports Complex Track Oval & LU Classrooms',
    14.2558,
    121.4042,
    true
  )
ON CONFLICT (id) DO UPDATE SET
  code = EXCLUDED.code,
  name = EXCLUDED.name,
  location_text = EXCLUDED.location_text,
  latitude = EXCLUDED.latitude,
  longitude = EXCLUDED.longitude,
  is_open = EXCLUDED.is_open,
  updated_at = now();

-- Update legacy codes (MAIN -> GATE1, ANNEX -> AVBLDG) if id differed
UPDATE public.terminals 
   SET name = 'Laguna University Gate 1 Terminal',
       location_text = 'Main Gate Entrance, Laguna University, Brgy. Bubukal, Sta. Cruz',
       latitude = 14.2575,
       longitude = 121.4048,
       updated_at = now()
 WHERE code = 'MAIN';

UPDATE public.terminals 
   SET name = 'LU AV Building Terminal',
       location_text = 'Audio-Visual Building / Academic Quadrangle, LU Campus',
       latitude = 14.2568,
       longitude = 121.4055,
       updated_at = now()
 WHERE code = 'ANNEX';

-- 2. Configure departure settings for all 3 terminals (4 passengers standard tricycle capacity)
INSERT INTO public.terminal_settings (terminal_id, departure_policy, min_passengers, almost_full_offset, stale_after_sec)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'min_threshold', 4, 1, 300),
  ('22222222-2222-2222-2222-222222222222', 'min_threshold', 4, 1, 300),
  ('33333333-3333-3333-3333-333333333333', 'min_threshold', 4, 1, 300)
ON CONFLICT (terminal_id) DO UPDATE SET
  departure_policy = EXCLUDED.departure_policy,
  min_passengers = EXCLUDED.min_passengers;
