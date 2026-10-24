-- =====================================================================
-- Migration 0005: Clean GPS Location-Sharing & Commuter Beacon Workflow
-- 
-- 1. Updates Laguna University Terminals (Gate 1, AV Building, Oval & Rooms in Bubukal)
-- 2. Adds landmark_hint, status, and driver assignment to commuter pings
-- 3. Adds calculate_commute_eta function for real-time ground distance & arrival ETA
-- 4. Updates signal_commuter_demand, respond_commuter_demand, and get_commuter_demand
-- =====================================================================

-- 1. Ensure Laguna University Terminals are registered with exact Bubukal GPS coordinates
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

-- Update legacy codes if id differed
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

INSERT INTO public.terminal_settings (terminal_id, departure_policy, min_passengers, almost_full_offset, stale_after_sec)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'min_threshold', 4, 1, 300),
  ('22222222-2222-2222-2222-222222222222', 'min_threshold', 4, 1, 300),
  ('33333333-3333-3333-3333-333333333333', 'min_threshold', 4, 1, 300)
ON CONFLICT (terminal_id) DO UPDATE SET
  departure_policy = EXCLUDED.departure_policy,
  min_passengers = EXCLUDED.min_passengers;

-- 2. Enhanced schema columns for terminal_commuter_pings, responses, and trips
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS landmark_hint TEXT;
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'waiting';
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS assigned_driver_id UUID REFERENCES auth.users(id);
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;

ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS passenger_count INT NOT NULL DEFAULT 1;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS is_special BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS pickup_lat DOUBLE PRECISION;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS pickup_lng DOUBLE PRECISION;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS pickup_label TEXT DEFAULT 'Gate 1 (Main Entrance)';

ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS is_special BOOLEAN NOT NULL DEFAULT false;

-- 3. Calculate distance (meters) and arrival ETA between 2 coordinates
CREATE OR REPLACE FUNCTION public.calculate_commute_eta(
    p_lat1 DOUBLE PRECISION,
    p_lng1 DOUBLE PRECISION,
    p_lat2 DOUBLE PRECISION,
    p_lng2 DOUBLE PRECISION
)
RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_r DOUBLE PRECISION := 6371000;
    v_dlat DOUBLE PRECISION := radians(p_lat2 - p_lat1);
    v_dlng DOUBLE PRECISION := radians(p_lng2 - p_lng1);
    v_a DOUBLE PRECISION;
    v_c DOUBLE PRECISION;
    v_meters INT;
    v_minutes INT;
BEGIN
    IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN
        RETURN jsonb_build_object('distance_meters', 0, 'distance_text', 'Near bay', 'eta_minutes', 1, 'eta_text', '~1 min');
    END IF;

    v_a := sin(v_dlat/2)^2 + cos(radians(p_lat1)) * cos(radians(p_lat2)) * sin(v_dlng/2)^2;
    v_c := 2 * atan2(sqrt(v_a), sqrt(1-v_a));
    v_meters := round(v_r * v_c);
    
    -- Average campus tricycle speed: 15 km/h (~250 meters / min) + 1 min prep
    v_minutes := greatest(1, round(v_meters / 250.0) + 1);
    
    RETURN jsonb_build_object(
        'distance_meters', v_meters,
        'distance_text', CASE WHEN v_meters >= 1000 THEN round((v_meters / 1000.0)::numeric, 1) || ' km' ELSE v_meters || ' meters' END,
        'eta_minutes', v_minutes,
        'eta_text', '~' || v_minutes || ' min' || CASE WHEN v_minutes > 1 THEN 's' ELSE '' END
    );
END;
$$;

-- 4. RPC: signal_commuter_demand
CREATE OR REPLACE FUNCTION public.signal_commuter_demand(
    p_terminal UUID,
    p_active BOOLEAN,
    p_passenger_count INT DEFAULT 1,
    p_is_special BOOLEAN DEFAULT false,
    p_pickup_lat DOUBLE PRECISION DEFAULT NULL,
    p_pickup_lng DOUBLE PRECISION DEFAULT NULL,
    p_pickup_label TEXT DEFAULT 'Gate 1 (Main Entrance)',
    p_landmark_hint TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_count INT;
    v_pax INT;
    v_term public.terminals;
    v_eta JSONB;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT * INTO v_term FROM public.terminals WHERE id = p_terminal;
    v_pax := GREATEST(1, LEAST(4, COALESCE(p_passenger_count, 1)));

    IF p_active THEN
        INSERT INTO public.terminal_commuter_pings (
            terminal_id, user_id, passenger_count, is_special, pickup_lat, pickup_lng, pickup_label, landmark_hint, status, created_at, expires_at
        )
        VALUES (
            p_terminal, v_user, v_pax, COALESCE(p_is_special, false), 
            COALESCE(p_pickup_lat, v_term.latitude, 14.2575), 
            COALESCE(p_pickup_lng, v_term.longitude, 121.4048), 
            COALESCE(p_pickup_label, 'Gate 1 (Main Entrance)'),
            p_landmark_hint,
            'waiting',
            now(), now() + INTERVAL '30 minutes'
        )
        ON CONFLICT (terminal_id, user_id)
        DO UPDATE SET 
            passenger_count = v_pax,
            is_special = COALESCE(p_is_special, false),
            pickup_lat = EXCLUDED.pickup_lat,
            pickup_lng = EXCLUDED.pickup_lng,
            pickup_label = EXCLUDED.pickup_label,
            landmark_hint = EXCLUDED.landmark_hint,
            status = 'waiting',
            assigned_driver_id = NULL,
            acknowledged_at = NULL,
            created_at = now(),
            expires_at = now() + INTERVAL '30 minutes';
    ELSE
        DELETE FROM public.terminal_commuter_pings
        WHERE terminal_id = p_terminal AND user_id = v_user;
    END IF;

    DELETE FROM public.terminal_commuter_pings WHERE expires_at <= now();

    SELECT COALESCE(SUM(passenger_count), 0) INTO v_count
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now();

    v_eta := public.calculate_commute_eta(
        v_term.latitude, v_term.longitude, 
        COALESCE(p_pickup_lat, v_term.latitude), 
        COALESCE(p_pickup_lng, v_term.longitude)
    );

    RETURN jsonb_build_object(
        'terminal_id', p_terminal,
        'active', p_active,
        'user_active', p_active,
        'total_waiting', v_count,
        'passenger_count', v_pax,
        'is_special', COALESCE(p_is_special, false),
        'pickup_lat', COALESCE(p_pickup_lat, v_term.latitude),
        'pickup_lng', COALESCE(p_pickup_lng, v_term.longitude),
        'pickup_label', COALESCE(p_pickup_label, 'Gate 1 (Main Entrance)'),
        'landmark_hint', p_landmark_hint,
        'distance_text', v_eta->>'distance_text',
        'eta_text', v_eta->>'eta_text'
    );
END;
$$;

-- 5. RPC: respond_commuter_demand
CREATE OR REPLACE FUNCTION public.respond_commuter_demand(
    p_terminal UUID,
    p_cancel BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_role public.user_role;
    v_driver_name TEXT;
    v_plate TEXT;
    v_count INT;
    v_pax INT := 1;
    v_special BOOLEAN := false;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_pickup_label TEXT;
    v_hint TEXT;
    v_ping_id UUID;
    v_term public.terminals;
    v_eta JSONB;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT role, full_name INTO v_role, v_driver_name
    FROM public.profiles WHERE id = v_user;

    IF v_role <> 'driver' THEN
        RAISE EXCEPTION 'Only authorized drivers can respond to commuter demand signals.';
    END IF;

    SELECT plate_no INTO v_plate FROM public.vehicles WHERE driver_id = v_user LIMIT 1;
    SELECT * INTO v_term FROM public.terminals WHERE id = p_terminal;

    IF p_cancel THEN
        DELETE FROM public.terminal_commuter_responses
        WHERE terminal_id = p_terminal AND driver_id = v_user;

        UPDATE public.terminal_commuter_pings
           SET status = 'waiting', assigned_driver_id = NULL, acknowledged_at = NULL
         WHERE terminal_id = p_terminal AND assigned_driver_id = v_user;
    ELSE
        -- Find student demand signal with coordinates
        SELECT id, passenger_count, is_special, pickup_lat, pickup_lng, pickup_label, landmark_hint
        INTO v_ping_id, v_pax, v_special, v_pickup_lat, v_pickup_lng, v_pickup_label, v_hint
        FROM public.terminal_commuter_pings
        WHERE terminal_id = p_terminal AND expires_at > now()
        ORDER BY created_at ASC
        LIMIT 1;

        v_pickup_lat := COALESCE(v_pickup_lat, v_term.latitude, 14.2575);
        v_pickup_lng := COALESCE(v_pickup_lng, v_term.longitude, 121.4048);
        v_pickup_label := COALESCE(v_pickup_label, 'Gate 1 (Main Entrance)');

        INSERT INTO public.terminal_commuter_responses (
            terminal_id, driver_id, driver_name, plate_no, passenger_count, is_special,
            pickup_lat, pickup_lng, pickup_label, responded_at, expires_at
        )
        VALUES (
            p_terminal, v_user, COALESCE(v_driver_name, 'Kuya Driver'), COALESCE(v_plate, 'LU-TRIKE'),
            v_pax, v_special, v_pickup_lat, v_pickup_lng, v_pickup_label,
            now(), now() + INTERVAL '15 minutes'
        )
        ON CONFLICT (terminal_id)
        DO UPDATE SET
            driver_id = EXCLUDED.driver_id,
            driver_name = EXCLUDED.driver_name,
            plate_no = EXCLUDED.plate_no,
            passenger_count = EXCLUDED.passenger_count,
            is_special = EXCLUDED.is_special,
            pickup_lat = EXCLUDED.pickup_lat,
            pickup_lng = EXCLUDED.pickup_lng,
            pickup_label = EXCLUDED.pickup_label,
            responded_at = now(),
            expires_at = now() + INTERVAL '15 minutes';

        -- Update ping status to acknowledged
        IF v_ping_id IS NOT NULL THEN
            UPDATE public.terminal_commuter_pings
               SET status = 'acknowledged', assigned_driver_id = v_user, acknowledged_at = now()
             WHERE id = v_ping_id;
        END IF;

        -- If Special trip, dispatch Queue #1
        IF v_special THEN
            DECLARE
                v_entry RECORD;
                v_entry_pos INT;
                v_veh_id UUID;
            BEGIN
                SELECT e.* INTO v_entry
                FROM public.terminal_queue_entries e
                WHERE e.driver_id = v_user 
                  AND e.terminal_id = p_terminal 
                  AND e.status IN ('waiting', 'boarding', 'almost_full', 'ready')
                LIMIT 1;

                IF v_entry.id IS NULL THEN
                    RAISE EXCEPTION 'You must be currently queued at the terminal to pick up solo trips.';
                END IF;

                SELECT count(*) + 1 INTO v_entry_pos
                FROM public.terminal_queue_entries q
                WHERE q.terminal_id = p_terminal
                  AND q.status IN ('waiting', 'boarding', 'almost_full', 'ready')
                  AND q.seq < v_entry.seq;

                IF v_entry_pos > 1 THEN
                    RAISE EXCEPTION 'Only the front driver in queue (Queue #1) is authorized to accept Solo / Special trips.';
                END IF;

                IF v_entry.passenger_count > 0 THEN
                    RAISE EXCEPTION 'You already have regular passengers boarded. Finish your current trip first.';
                END IF;

                UPDATE public.terminal_queue_entries
                   SET status = 'departed', ended_at = now(), end_reason = 'special_gate_dispatch', is_special = true,
                       version = version + 1, updated_at = now()
                 WHERE id = v_entry.id;

                -- Fallback to entry vehicle_id if vehicles table query returns null
                SELECT id INTO v_veh_id FROM public.vehicles WHERE driver_id = v_user LIMIT 1;
                v_veh_id := COALESCE(v_veh_id, v_entry.vehicle_id);

                IF v_veh_id IS NOT NULL THEN
                    INSERT INTO public.trips (queue_entry_id, terminal_id, driver_id, vehicle_id, passenger_count, is_special, wait_seconds)
                    VALUES (v_entry.id, p_terminal, v_user, v_veh_id, 1, true, 0)
                    ON CONFLICT (queue_entry_id) DO NOTHING;
                END IF;

                PERFORM public.log_activity(v_entry.id, p_terminal, v_user, 'departed_gate_pickup', jsonb_build_object('is_special', true));
                PERFORM public.notify_terminal(
                    p_terminal, 
                    'students', 
                    'departed', 
                    'Tricycle en route to pickup',
                    'Driver ' || COALESCE(v_driver_name, 'Kuya Driver') || ' is on the way to ' || COALESCE(v_pickup_label, 'campus pickup spot') || ' for pick-up.', 
                    'dp:' || v_entry.id
                );
                PERFORM public.q_recompute(p_terminal);
            END;
        END IF;
    END IF;

    DELETE FROM public.terminal_commuter_responses WHERE expires_at <= now();

    SELECT COALESCE(SUM(passenger_count), 0) INTO v_count
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now();

    v_eta := public.calculate_commute_eta(v_term.latitude, v_term.longitude, v_pickup_lat, v_pickup_lng);

    RETURN jsonb_build_object(
        'terminal_id', p_terminal,
        'responded', NOT p_cancel,
        'driver_name', v_driver_name,
        'plate_no', v_plate,
        'passenger_count', v_pax,
        'is_special', v_special,
        'pickup_lat', v_pickup_lat,
        'pickup_lng', v_pickup_lng,
        'pickup_label', v_pickup_label,
        'landmark_hint', v_hint,
        'distance_text', v_eta->>'distance_text',
        'eta_text', v_eta->>'eta_text',
        'total_waiting', v_count
    );
END;
$$;

-- 6. RPC: get_commuter_demand
CREATE OR REPLACE FUNCTION public.get_commuter_demand(p_terminal UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_total_pax INT;
    v_total_requests INT;
    v_has_special BOOLEAN := false;
    v_user_active BOOLEAN := false;
    v_my_pax INT := 1;
    v_my_special BOOLEAN := false;
    v_pickup_lat DOUBLE PRECISION;
    v_pickup_lng DOUBLE PRECISION;
    v_pickup_label TEXT;
    v_hint TEXT;
    v_status TEXT := 'waiting';
    v_my_pickup_label TEXT;
    v_my_hint TEXT;
    v_resp RECORD;
    v_incoming JSONB := NULL;
    v_is_my_response BOOLEAN := false;
    v_term public.terminals;
    v_eta JSONB;
BEGIN
    DELETE FROM public.terminal_commuter_pings WHERE expires_at <= now();
    DELETE FROM public.terminal_commuter_responses WHERE expires_at <= now();

    SELECT * INTO v_term FROM public.terminals WHERE id = p_terminal;

    SELECT COALESCE(SUM(passenger_count), 0), COUNT(*), COALESCE(BOOL_OR(is_special), false)
    INTO v_total_pax, v_total_requests, v_has_special
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now();

    -- Get student's pinned waypoint
    SELECT pickup_lat, pickup_lng, pickup_label, landmark_hint, status
    INTO v_pickup_lat, v_pickup_lng, v_pickup_label, v_hint, v_status
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now()
    ORDER BY created_at ASC
    LIMIT 1;

    IF v_user IS NOT NULL THEN
        SELECT true, passenger_count, is_special, pickup_label, landmark_hint, status
        INTO v_user_active, v_my_pax, v_my_special, v_my_pickup_label, v_my_hint, v_status
        FROM public.terminal_commuter_pings
        WHERE terminal_id = p_terminal AND user_id = v_user AND expires_at > now();
    END IF;

    SELECT driver_id, driver_name, plate_no, passenger_count, is_special, pickup_lat, pickup_lng, pickup_label, responded_at INTO v_resp
    FROM public.terminal_commuter_responses
    WHERE terminal_id = p_terminal AND expires_at > now();

    IF FOUND THEN
        v_incoming := jsonb_build_object(
            'driver_id', v_resp.driver_id,
            'driver_name', v_resp.driver_name,
            'plate_no', v_resp.plate_no,
            'passenger_count', v_resp.passenger_count,
            'is_special', v_resp.is_special,
            'pickup_lat', v_resp.pickup_lat,
            'pickup_lng', v_resp.pickup_lng,
            'pickup_label', v_resp.pickup_label,
            'responded_at', v_resp.responded_at
        );
        IF v_user IS NOT NULL AND v_user = v_resp.driver_id THEN
            v_is_my_response := true;
        END IF;
    END IF;

    v_eta := public.calculate_commute_eta(
        v_term.latitude, v_term.longitude,
        COALESCE(v_pickup_lat, v_term.latitude),
        COALESCE(v_pickup_lng, v_term.longitude)
    );

    RETURN jsonb_build_object(
        'terminal_id', p_terminal,
        'user_active', COALESCE(v_user_active, false),
        'total_waiting', v_total_pax,
        'total_requests', v_total_requests,
        'has_special', v_has_special,
        'my_passenger_count', COALESCE(v_my_pax, 1),
        'my_is_special', COALESCE(v_my_special, false),
        'pickup_lat', COALESCE(v_pickup_lat, v_term.latitude),
        'pickup_lng', COALESCE(v_pickup_lng, v_term.longitude),
        'pickup_label', COALESCE(v_pickup_label, 'Gate 1 (Main Entrance)'),
        'landmark_hint', COALESCE(v_my_hint, v_hint),
        'my_pickup_label', v_my_pickup_label,
        'status', v_status,
        'distance_meters', v_eta->'distance_meters',
        'distance_text', v_eta->>'distance_text',
        'eta_minutes', v_eta->'eta_minutes',
        'eta_text', v_eta->>'eta_text',
        'incoming_driver', v_incoming,
        'is_my_response', v_is_my_response
    );
END;
$$;

-- Permissions
GRANT EXECUTE ON FUNCTION public.calculate_commute_eta(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.signal_commuter_demand(UUID, BOOLEAN, INT, BOOLEAN, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_commuter_demand(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_commuter_demand(UUID) TO authenticated, anon;
