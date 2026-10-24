-- ===========================================================================
-- MIGRATION 0006: Smart Commuter Dispatch Rules (Solo vs. Regular Shared)
-- ===========================================================================
-- 1. Fix driver_board_demand to ACCUMULATE passengers instead of overwriting.
--    (e.g., 3 walk-ins + 1 gate demand passenger = 4 passengers [FULL]).
-- 2. Enhance respond_commuter_demand:
--    - Solo/Special Trip: Reserved for the first empty tricycle (passenger_count = 0).
--      If Queue #1 already has passengers, Queue #1 cannot accept; Queue #2 (empty) can.
--    - Regular Shared Trip: Prevents accepting if remaining capacity < demand pax.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.driver_board_demand(
    p_count INT DEFAULT 1,
    p_is_special BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_entry public.terminal_queue_entries;
    v_settings public.terminal_settings;
    v_new_count INT;
    v_new_status public.queue_status;
BEGIN
    v_entry := public.q_lock_my_entry();
    SELECT * INTO v_settings FROM public.terminal_settings WHERE terminal_id = v_entry.terminal_id;

    IF p_is_special THEN
        -- Solo / Special Trip: 1 pax, marked ready immediately for instant departure
        v_new_count := 1;
        v_new_status := 'ready';
    ELSE
        -- ACCUMULATE: Add new boarding passengers to existing passenger count
        v_new_count := LEAST(v_entry.capacity_snapshot, v_entry.passenger_count + GREATEST(1, COALESCE(p_count, 1)));
        IF public.q_policy_satisfied(v_new_count, v_entry.capacity_snapshot, v_settings) THEN
            v_new_status := 'ready';
        ELSE
            v_new_status := public.q_boarding_status(v_new_count, v_entry.capacity_snapshot, v_settings.almost_full_offset);
        END IF;
    END IF;

    UPDATE public.terminal_queue_entries
    SET passenger_count = v_new_count,
        is_special = COALESCE(p_is_special, false),
        status = v_new_status,
        ready_at = CASE WHEN v_new_status = 'ready' THEN now() ELSE NULL END,
        version = version + 1,
        updated_at = now()
    WHERE id = v_entry.id
    RETURNING * INTO v_entry;

    -- Clean up active commitment for this terminal
    DELETE FROM public.terminal_commuter_responses WHERE terminal_id = v_entry.terminal_id;
    DELETE FROM public.terminal_commuter_pings WHERE terminal_id = v_entry.terminal_id;

    RETURN jsonb_build_object(
        'entry_id', v_entry.id,
        'passenger_count', v_new_count,
        'status', v_new_status,
        'is_special', p_is_special
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_board_demand(INT, BOOLEAN) TO authenticated;

-- ===========================================================================
-- Enhanced respond_commuter_demand
-- ===========================================================================
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

        -- Verify driver entry eligibility in queue
        DECLARE
            v_entry RECORD;
            v_entry_pos INT;
            v_first_empty_pos INT;
            v_seats_left INT;
            v_veh_id UUID;
        BEGIN
            SELECT e.* INTO v_entry
            FROM public.terminal_queue_entries e
            WHERE e.driver_id = v_user 
              AND e.terminal_id = p_terminal 
              AND e.status IN ('waiting', 'boarding', 'almost_full', 'ready')
            LIMIT 1;

            IF v_entry.id IS NULL THEN
                RAISE EXCEPTION 'You must be currently queued at the terminal to pick up students.';
            END IF;

            IF v_special THEN
                -- Solo Trip Rule: Driver must have 0 passengers currently boarded
                IF v_entry.passenger_count > 0 THEN
                    RAISE EXCEPTION 'Bawal ang Solo Trip dahil may % regular passenger(s) ka nang nakasakay. Tapusin muna ang kasalukuyang boarding.', v_entry.passenger_count;
                END IF;

                -- Must be the first empty tricycle in queue
                SELECT count(*) + 1 INTO v_first_empty_pos
                FROM public.terminal_queue_entries q
                WHERE q.terminal_id = p_terminal
                  AND q.status IN ('waiting', 'boarding', 'almost_full', 'ready')
                  AND q.passenger_count = 0
                  AND q.seq < v_entry.seq;

                IF v_first_empty_pos > 1 THEN
                    RAISE EXCEPTION 'Nakalaan ang Solo Trip sa naunang bakanteng tricycle sa pila.';
                END IF;

                -- Instant Solo Trip dispatch from queue
                UPDATE public.terminal_queue_entries
                   SET status = 'departed', ended_at = now(), end_reason = 'special_gate_dispatch', is_special = true,
                       version = version + 1, updated_at = now()
                 WHERE id = v_entry.id;

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
            ELSE
                -- Regular Shared Trip Rule: Check if driver has enough remaining seats
                v_seats_left := v_entry.capacity_snapshot - v_entry.passenger_count;
                IF v_seats_left < v_pax THEN
                    RAISE EXCEPTION 'Kulang ang bakanteng upuan (% natitira, kailangan ng %). Nakalaan ang grupong ito sa susunod na tricycle.', v_seats_left, v_pax;
                END IF;

                -- Check queue priority among tricycles with enough seats
                SELECT count(*) + 1 INTO v_entry_pos
                FROM public.terminal_queue_entries q
                WHERE q.terminal_id = p_terminal
                  AND q.status IN ('waiting', 'boarding', 'almost_full', 'ready')
                  AND (q.capacity_snapshot - q.passenger_count) >= v_pax
                  AND q.seq < v_entry.seq;

                IF v_entry_pos > 1 THEN
                    RAISE EXCEPTION 'Nakalaan ang pagsundo sa naunang tricycle sa pila na may sapat na upuan.';
                END IF;
            END IF;
        END;

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

GRANT EXECUTE ON FUNCTION public.respond_commuter_demand(UUID, BOOLEAN) TO authenticated;
