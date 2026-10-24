-- ============================================================================
-- 0004_commuter_pings.sql: Late-Night & High-Demand Commuter Signal Beacon
-- Supports:
-- 1. Party Size (1 to 4 passengers)
-- 2. Solo / Special Trip Mode (authorized for immediate departure)
-- 3. Driver En Route Handshake & 1-Tap Boarding
-- 4. Automatic Solo Dispatch (Departure with 1 pax without waiting for 4 pax)
-- ============================================================================

-- Ensure queue entries & trips support special/solo trip departure flag
ALTER TABLE public.terminal_queue_entries ADD COLUMN IF NOT EXISTS is_special BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.trips ADD COLUMN IF NOT EXISTS is_special BOOLEAN NOT NULL DEFAULT false;

-- Table 1: Student Demand Signals (Waiting at gate)
CREATE TABLE IF NOT EXISTS public.terminal_commuter_pings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    terminal_id UUID NOT NULL REFERENCES public.terminals(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    passenger_count INT NOT NULL DEFAULT 1,
    is_special BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 minutes'),
    CONSTRAINT terminal_commuter_unique UNIQUE (terminal_id, user_id)
);

ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS passenger_count INT NOT NULL DEFAULT 1;
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS is_special BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS pickup_lat DOUBLE PRECISION;
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS pickup_lng DOUBLE PRECISION;
ALTER TABLE public.terminal_commuter_pings ADD COLUMN IF NOT EXISTS pickup_label TEXT DEFAULT 'Main Gate (Waiting Shed)';

CREATE INDEX IF NOT EXISTS idx_commuter_pings_active 
ON public.terminal_commuter_pings(terminal_id, expires_at);

ALTER TABLE public.terminal_commuter_pings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view active pings count" ON public.terminal_commuter_pings;
CREATE POLICY "Users can view active pings count"
ON public.terminal_commuter_pings
FOR SELECT
TO authenticated
USING (expires_at > now());

DROP POLICY IF EXISTS "Students can manage own pings" ON public.terminal_commuter_pings;
CREATE POLICY "Students can manage own pings"
ON public.terminal_commuter_pings
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Table 2: Driver Response / En Route Commitments
CREATE TABLE IF NOT EXISTS public.terminal_commuter_responses (
    terminal_id UUID PRIMARY KEY REFERENCES public.terminals(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    driver_name TEXT NOT NULL,
    plate_no TEXT NOT NULL,
    passenger_count INT NOT NULL DEFAULT 1,
    is_special BOOLEAN NOT NULL DEFAULT false,
    pickup_lat DOUBLE PRECISION,
    pickup_lng DOUBLE PRECISION,
    pickup_label TEXT DEFAULT 'Main Gate (Waiting Shed)',
    responded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '15 minutes')
);

ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS passenger_count INT NOT NULL DEFAULT 1;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS is_special BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS pickup_lat DOUBLE PRECISION;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS pickup_lng DOUBLE PRECISION;
ALTER TABLE public.terminal_commuter_responses ADD COLUMN IF NOT EXISTS pickup_label TEXT DEFAULT 'Main Gate (Waiting Shed)';

ALTER TABLE public.terminal_commuter_responses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view driver commitments" ON public.terminal_commuter_responses;
CREATE POLICY "Users can view driver commitments"
ON public.terminal_commuter_responses
FOR SELECT
TO authenticated
USING (expires_at > now());

DROP POLICY IF EXISTS "Drivers can manage responses" ON public.terminal_commuter_responses;
CREATE POLICY "Drivers can manage responses"
ON public.terminal_commuter_responses
FOR ALL
TO authenticated
USING (driver_id = auth.uid())
WITH CHECK (driver_id = auth.uid());

-- RPC 1: Activate or cancel student demand signal with party size, special trip mode & custom pickup pin
CREATE OR REPLACE FUNCTION public.signal_commuter_demand(
    p_terminal UUID,
    p_active BOOLEAN,
    p_passenger_count INT DEFAULT 1,
    p_is_special BOOLEAN DEFAULT false,
    p_pickup_lat DOUBLE PRECISION DEFAULT NULL,
    p_pickup_lng DOUBLE PRECISION DEFAULT NULL,
    p_pickup_label TEXT DEFAULT 'Main Gate (Waiting Shed)'
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
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    v_pax := GREATEST(1, LEAST(4, COALESCE(p_passenger_count, 1)));

    IF p_active THEN
        INSERT INTO public.terminal_commuter_pings (
            terminal_id, user_id, passenger_count, is_special, pickup_lat, pickup_lng, pickup_label, created_at, expires_at
        )
        VALUES (
            p_terminal, v_user, v_pax, COALESCE(p_is_special, false), p_pickup_lat, p_pickup_lng, COALESCE(p_pickup_label, 'Main Gate (Waiting Shed)'), now(), now() + INTERVAL '30 minutes'
        )
        ON CONFLICT (terminal_id, user_id)
        DO UPDATE SET 
            passenger_count = v_pax,
            is_special = COALESCE(p_is_special, false),
            pickup_lat = EXCLUDED.pickup_lat,
            pickup_lng = EXCLUDED.pickup_lng,
            pickup_label = EXCLUDED.pickup_label,
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

    RETURN jsonb_build_object(
        'terminal_id', p_terminal,
        'active', p_active,
        'user_active', p_active,
        'total_waiting', v_count,
        'passenger_count', v_pax,
        'is_special', COALESCE(p_is_special, false),
        'pickup_lat', p_pickup_lat,
        'pickup_lng', p_pickup_lng,
        'pickup_label', COALESCE(p_pickup_label, 'Main Gate (Waiting Shed)')
    );
END;
$$;

-- RPC 2: Driver responds "Heading to Gate" / cancels commitment
-- When accepting a Solo/Special trip, automatically marks driver's queue entry as special & ready!
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
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT role, full_name INTO v_role, v_driver_name
    FROM public.profiles
    WHERE id = v_user;

    IF v_role != 'driver' THEN
        RAISE EXCEPTION 'Only verified drivers can respond to commuter demand signals.';
    END IF;

    SELECT plate_no INTO v_plate
    FROM public.vehicles
    WHERE driver_id = v_user
    LIMIT 1;

    IF v_plate IS NULL THEN
        v_plate := 'LU-TRIKE';
    END IF;

    IF p_cancel THEN
        DELETE FROM public.terminal_commuter_responses
        WHERE terminal_id = p_terminal AND driver_id = v_user;

        -- Revert special status on active entry if cancelled
        UPDATE public.terminal_queue_entries
        SET is_special = false,
            updated_at = now()
        WHERE driver_id = v_user 
          AND terminal_id = p_terminal 
          AND is_special = true;
    ELSE
        -- Get current demand attributes and student's pinned location
        SELECT COALESCE(MAX(passenger_count), 1), COALESCE(BOOL_OR(is_special), false)
        INTO v_pax, v_special
        FROM public.terminal_commuter_pings
        WHERE terminal_id = p_terminal AND expires_at > now();

        SELECT pickup_lat, pickup_lng, pickup_label
        INTO v_pickup_lat, v_pickup_lng, v_pickup_label
        FROM public.terminal_commuter_pings
        WHERE terminal_id = p_terminal AND expires_at > now()
        ORDER BY created_at ASC
        LIMIT 1;

        v_pax := COALESCE(v_pax, 1);
        v_special := COALESCE(v_special, false);
        v_pickup_label := COALESCE(v_pickup_label, 'Main Gate (Waiting Shed)');

        INSERT INTO public.terminal_commuter_responses (
            terminal_id, driver_id, driver_name, plate_no, passenger_count, is_special, pickup_lat, pickup_lng, pickup_label, responded_at, expires_at
        )
        VALUES (
            p_terminal, v_user, v_driver_name, v_plate, v_pax, v_special, v_pickup_lat, v_pickup_lng, v_pickup_label, now(), now() + INTERVAL '15 minutes'
        )
        ON CONFLICT (terminal_id)
        DO UPDATE SET 
            driver_id = v_user,
            driver_name = v_driver_name,
            plate_no = v_plate,
            passenger_count = v_pax,
            is_special = v_special,
            pickup_lat = v_pickup_lat,
            pickup_lng = v_pickup_lng,
            pickup_label = v_pickup_label,
            responded_at = now(),
            expires_at = now() + INTERVAL '15 minutes';

        -- Enforce Toda queue fairness on gate pick-ups:
        -- 1. Caller MUST be currently queued at the terminal
        -- 2. Caller MUST be Queue #1 (front driver)
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
                RAISE EXCEPTION 'TODA Rule: You must be currently queued at the terminal to pick up students.';
            END IF;

            SELECT count(*) + 1 INTO v_entry_pos
            FROM public.terminal_queue_entries q
            WHERE q.terminal_id = p_terminal
              AND q.status IN ('waiting', 'boarding', 'almost_full', 'ready')
              AND q.seq < v_entry.seq;

            IF v_entry_pos > 1 THEN
                RAISE EXCEPTION 'TODA Rule: Only the front driver in queue (Queue #1) is authorized to respond to gate pick-ups.';
            END IF;

            IF v_special THEN
                IF v_entry.passenger_count > 0 THEN
                    RAISE EXCEPTION 'You already have regular passengers boarded. Finish your current trip first.';
                END IF;

                -- Depart from terminal bay to advance queue for next driver in line!
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
            END IF;
        END;
    END IF;

    DELETE FROM public.terminal_commuter_responses WHERE expires_at <= now();

    SELECT COALESCE(SUM(passenger_count), 0) INTO v_count
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now();

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
        'total_waiting', v_count
    );
END;
$$;

-- RPC 3: Query current demand count, party size, special trip flag, & incoming driver info
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
    v_my_pickup_label TEXT;
    v_resp RECORD;
    v_incoming JSONB := NULL;
    v_is_my_response BOOLEAN := false;
BEGIN
    DELETE FROM public.terminal_commuter_pings WHERE expires_at <= now();
    DELETE FROM public.terminal_commuter_responses WHERE expires_at <= now();

    SELECT COALESCE(SUM(passenger_count), 0), COUNT(*), COALESCE(BOOL_OR(is_special), false)
    INTO v_total_pax, v_total_requests, v_has_special
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now();

    -- Get student's pinned location
    SELECT pickup_lat, pickup_lng, pickup_label
    INTO v_pickup_lat, v_pickup_lng, v_pickup_label
    FROM public.terminal_commuter_pings
    WHERE terminal_id = p_terminal AND expires_at > now()
    ORDER BY created_at ASC
    LIMIT 1;

    IF v_user IS NOT NULL THEN
        SELECT true, passenger_count, is_special, pickup_label
        INTO v_user_active, v_my_pax, v_my_special, v_my_pickup_label
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

    RETURN jsonb_build_object(
        'terminal_id', p_terminal,
        'user_active', COALESCE(v_user_active, false),
        'total_waiting', v_total_pax,
        'total_requests', v_total_requests,
        'has_special', v_has_special,
        'my_passenger_count', COALESCE(v_my_pax, 1),
        'my_is_special', COALESCE(v_my_special, false),
        'pickup_lat', v_pickup_lat,
        'pickup_lng', v_pickup_lng,
        'pickup_label', COALESCE(v_pickup_label, 'Main Gate (Waiting Shed)'),
        'my_pickup_label', v_my_pickup_label,
        'incoming_driver', v_incoming,
        'is_my_response', v_is_my_response
    );
END;
$$;

-- RPC 4: 1-Tap Board Waiting Commuters (Handles Special/Solo Trip departure authorization)
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
        v_new_count := GREATEST(1, LEAST(v_entry.capacity_snapshot, COALESCE(p_count, 1)));
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

-- RPC 5: OVERRIDE driver_confirm_departure to authorize Solo/Special trip departure with 1 pax
CREATE OR REPLACE FUNCTION public.driver_confirm_departure() RETURNS public.trips
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    e public.terminal_queue_entries;
    s public.terminal_settings;
    tr public.trips;
BEGIN
    e := public.q_lock_my_entry();
    SELECT * INTO s FROM public.terminal_settings WHERE terminal_id = e.terminal_id;

    IF e.status <> 'ready' THEN
        PERFORM public.fail('INVALID_STATE', 'Mark the tricycle as "Ready to depart" before confirming departure.');
    END IF;

    -- Solo/Special trips bypass the standard full-capacity requirement (no need for 4 pax)!
    IF NOT (COALESCE(e.is_special, false) OR public.q_policy_satisfied(e.passenger_count, e.capacity_snapshot, s)) THEN
        PERFORM public.fail('POLICY_NOT_MET', 'Departure requirement is no longer met.');
    END IF;

    UPDATE public.terminal_queue_entries
       SET status = 'departed', ended_at = now(), end_reason = 'departed', version = version + 1, updated_at = now()
     WHERE id = e.id RETURNING * INTO e;

    INSERT INTO public.trips (queue_entry_id, terminal_id, driver_id, vehicle_id, passenger_count, is_special, wait_seconds)
    VALUES (e.id, e.terminal_id, e.driver_id, e.vehicle_id, e.passenger_count, COALESCE(e.is_special, false),
            extract(epoch from (now() - e.joined_at))::int)
    RETURNING * INTO tr;

    PERFORM public.log_activity(e.id, e.terminal_id, e.driver_id, 'departed',
        jsonb_build_object('passengers', e.passenger_count, 'is_special', COALESCE(e.is_special, false)));

    PERFORM public.notify_terminal(e.terminal_id, 'students', 'departed', 'Tricycle departed',
      CASE WHEN COALESCE(e.is_special, false) THEN 'A solo/special trip tricycle has departed.'
           ELSE 'A tricycle with ' || e.passenger_count || ' passenger(s) has departed.' END, 'dp:' || e.id);

    PERFORM public.q_recompute(e.terminal_id);
    RETURN tr;
END;
$$;

-- RPC 6: OVERRIDE driver_mark_ready to support Solo/Special trips
CREATE OR REPLACE FUNCTION public.driver_mark_ready() RETURNS public.terminal_queue_entries
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    e public.terminal_queue_entries;
    s public.terminal_settings;
BEGIN
    e := public.q_lock_my_entry();
    SELECT * INTO s FROM public.terminal_settings WHERE terminal_id = e.terminal_id;
    IF e.status NOT IN ('boarding','almost_full') THEN
        PERFORM public.fail('INVALID_STATE', 'Only a tricycle accepting passengers can be marked ready.');
    END IF;
    IF NOT (COALESCE(e.is_special, false) OR public.q_policy_satisfied(e.passenger_count, e.capacity_snapshot, s)) THEN
        PERFORM public.fail('POLICY_NOT_MET', 'Departure requirement not met yet (' ||
          coalesce(public.q_needed(e.passenger_count, e.capacity_snapshot, s)::text, 'more') || ' more passenger(s) needed).');
    END IF;
    UPDATE public.terminal_queue_entries SET status = 'ready', ready_at = now(), version = version + 1, updated_at = now()
     WHERE id = e.id RETURNING * INTO e;
    PERFORM public.log_activity(e.id, e.terminal_id, e.driver_id, 'marked_ready',
        jsonb_build_object('passengers', e.passenger_count, 'is_special', COALESCE(e.is_special, false)));
    PERFORM public.notify_terminal(e.terminal_id, 'students', 'ready', 'Tricycle ready to depart',
      CASE WHEN COALESCE(e.is_special, false) THEN 'A solo/special trip tricycle is ready to depart.'
           ELSE 'A tricycle is ready to depart. The next tricycle is now accepting passengers.' END, 'rd:' || e.id);
    PERFORM public.q_recompute(e.terminal_id);
    RETURN e;
END;
$$;

-- RPC 7: OVERRIDE get_driver_status to expose is_special flag and adjust needed/policy_satisfied
CREATE OR REPLACE FUNCTION public.get_driver_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    p public.profiles;
    d public.driver_profiles;
    v public.vehicles;
    t public.terminals;
    s public.terminal_settings;
    e public.terminal_queue_entries;
    pos int;
    tr public.trips;
    req public.driver_verification_requests;
BEGIN
    SELECT * INTO p FROM public.profiles WHERE id = auth.uid() AND role = 'driver';
    IF NOT FOUND THEN PERFORM public.fail('NOT_DRIVER', 'Driver account required.'); END IF;
    SELECT * INTO d FROM public.driver_profiles WHERE profile_id = p.id;
    SELECT * INTO v FROM public.vehicles WHERE driver_id = p.id ORDER BY created_at LIMIT 1;
    SELECT * INTO t FROM public.terminals WHERE id = d.assigned_terminal_id;
    SELECT * INTO s FROM public.terminal_settings WHERE terminal_id = d.assigned_terminal_id;
    SELECT * INTO req FROM public.driver_verification_requests WHERE driver_id = p.id ORDER BY created_at DESC LIMIT 1;
    SELECT * INTO e FROM public.terminal_queue_entries
     WHERE driver_id = p.id AND status = ANY (public.q_active_statuses()) LIMIT 1;

    IF e.id IS NOT NULL AND e.status <> 'paused' THEN
        SELECT count(*) + 1 INTO pos FROM public.terminal_queue_entries
         WHERE terminal_id = e.terminal_id AND status IN ('waiting','boarding','almost_full','ready') AND seq < e.seq;
    END IF;

    SELECT * INTO tr FROM public.trips WHERE driver_id = p.id AND returned_at IS NULL ORDER BY departed_at DESC LIMIT 1;

    RETURN jsonb_build_object(
        'profile', jsonb_build_object('id', p.id, 'full_name', p.full_name, 'status', p.status, 'status_reason', p.status_reason),
        'driver', jsonb_build_object('contact_no', d.contact_no, 'license_no', d.license_no),
        'vehicle', CASE WHEN v.id IS NULL THEN NULL ELSE to_jsonb(v) END,
        'terminal', CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object(
            'id', t.id, 'name', t.name, 'code', t.code, 'location_text', t.location_text,
            'is_open', t.is_open, 'closed_reason', t.closed_reason,
            'is_operating', public.terminal_is_operating(t.id)) END,
        'settings', CASE WHEN s.terminal_id IS NULL THEN NULL ELSE to_jsonb(s) END,
        'verification', CASE WHEN req.id IS NULL THEN NULL ELSE jsonb_build_object('status', req.status, 'notes', req.notes) END,
        'entry', CASE WHEN e.id IS NULL THEN NULL ELSE to_jsonb(e) || jsonb_build_object(
            'position', pos,
            'seats_left', e.capacity_snapshot - e.passenger_count,
            'is_special', COALESCE(e.is_special, false),
            'needed', CASE WHEN COALESCE(e.is_special, false) THEN 0 ELSE public.q_needed(e.passenger_count, e.capacity_snapshot, s) END,
            'policy_satisfied', (COALESCE(e.is_special, false) OR public.q_policy_satisfied(e.passenger_count, e.capacity_snapshot, s))) END,
        'open_trip', CASE WHEN tr.id IS NULL THEN NULL ELSE to_jsonb(tr) END,
        'server_time', now());
END;
$$;

-- Permissions
GRANT EXECUTE ON FUNCTION public.signal_commuter_demand(UUID, BOOLEAN, INT, BOOLEAN, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_commuter_demand(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_commuter_demand(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.driver_board_demand(INT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_confirm_departure() TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_mark_ready() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_driver_status() TO authenticated;
