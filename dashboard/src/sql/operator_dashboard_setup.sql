-- ==============================================================================
-- SORYNTH RESCUE COMMAND DASHBOARD - OPERATOR SETUP (HARDENED LEAST PRIVILEGE)
-- File: src/sql/operator_dashboard_setup.sql
-- ==============================================================================
-- NOTE: The canonical, comprehensive RBAC migration is located in:
--   src/sql/rbac_schema_setup.sql
-- This setup script is aligned with strict least-privilege standards:
--   1. Zero table privileges granted to anon or PUBLIC.
--   2. RLS policies strictly scoped to active operators and Super Admins.
--   3. RPCs hardened against unauthorized anonymous execution.
-- ==============================================================================

-- 1. ENSURE RESCUE ROLE COLUMN EXISTS ON PROFILES
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'profiles' 
          AND column_name = 'rescue_role'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN rescue_role rescue_role_enum DEFAULT 'COMMANDER';
    END IF;
END $$;

-- 2. GRANT CORE TABLE PERMISSIONS (LEAST PRIVILEGE: ANON/PUBLIC STRICTLY REVOKED)
REVOKE ALL ON public.emergencies FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.emergencies FROM anon, PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.emergencies TO authenticated;

REVOKE ALL ON public.rescue_teams FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.rescue_teams FROM anon, PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.rescue_teams TO authenticated;

-- relay_logs: Anon and PUBLIC completely revoked. Authenticated SELECT only.
REVOKE ALL PRIVILEGES ON public.relay_logs FROM anon, PUBLIC;
REVOKE ALL ON public.relay_logs FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.relay_logs FROM anon, PUBLIC;
REVOKE ALL PRIVILEGES ON public.relay_logs FROM authenticated;
REVOKE ALL ON public.relay_logs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.relay_logs FROM authenticated;
GRANT SELECT ON public.relay_logs TO authenticated;

REVOKE ALL ON public.emergency_updates FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.emergency_updates FROM anon, PUBLIC;
GRANT SELECT, INSERT ON public.emergency_updates TO authenticated;

REVOKE ALL ON public.profiles FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.profiles FROM anon, PUBLIC;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;

-- Conditional permissions for operator_profiles if it exists in schema
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'operator_profiles'
    ) THEN
        REVOKE ALL ON public.operator_profiles FROM anon, PUBLIC;
        EXECUTE 'REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.operator_profiles FROM anon, PUBLIC';
        EXECUTE 'GRANT SELECT, UPDATE ON public.operator_profiles TO authenticated';
        EXECUTE 'ALTER TABLE public.operator_profiles ENABLE ROW LEVEL SECURITY';
        EXECUTE 'DROP POLICY IF EXISTS "Allow read operator profiles" ON public.operator_profiles';
        EXECUTE 'DROP POLICY IF EXISTS "Allow manage operator profiles" ON public.operator_profiles';
        EXECUTE 'DROP POLICY IF EXISTS "Operator profiles select policy" ON public.operator_profiles';
        EXECUTE 'CREATE POLICY "Operator profiles select policy" ON public.operator_profiles FOR SELECT TO authenticated USING (public.is_super_admin(auth.uid()) OR user_id = auth.uid())';
    END IF;
END $$;

-- 3. RLS POLICIES FOR EMERGENCIES TABLE
ALTER TABLE public.emergencies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Operators can view all emergencies" ON public.emergencies;
DROP POLICY IF EXISTS "Emergencies select policy" ON public.emergencies;
CREATE POLICY "Emergencies select policy"
    ON public.emergencies FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()));

DROP POLICY IF EXISTS "Operators can update all emergencies" ON public.emergencies;
DROP POLICY IF EXISTS "Emergencies update policy" ON public.emergencies;
CREATE POLICY "Emergencies update policy"
    ON public.emergencies FOR UPDATE
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()))
    WITH CHECK (
        public.is_super_admin(auth.uid()) 
        OR (
            public.is_active_operator(auth.uid()) 
            AND status IN ('ACKNOWLEDGED', 'IN_ACTION', 'RESOLVED', 'CANCELLED', 'PENDING')
        )
    );

DROP POLICY IF EXISTS "Operators can insert emergencies" ON public.emergencies;
DROP POLICY IF EXISTS "Emergencies insert policy" ON public.emergencies;
CREATE POLICY "Emergencies insert policy"
    ON public.emergencies FOR INSERT
    TO authenticated
    WITH CHECK (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()));

DROP POLICY IF EXISTS "Operators can delete emergencies" ON public.emergencies;
DROP POLICY IF EXISTS "Emergencies delete policy" ON public.emergencies;
CREATE POLICY "Emergencies delete policy"
    ON public.emergencies FOR DELETE
    TO authenticated
    USING (public.is_super_admin(auth.uid()));

-- 4. RLS POLICIES FOR RESCUE TEAMS
ALTER TABLE public.rescue_teams ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read rescue teams" ON public.rescue_teams;
DROP POLICY IF EXISTS "Rescue teams select policy" ON public.rescue_teams;
CREATE POLICY "Rescue teams select policy"
    ON public.rescue_teams FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()));

DROP POLICY IF EXISTS "Allow manage rescue teams" ON public.rescue_teams;
DROP POLICY IF EXISTS "Rescue teams manage policy" ON public.rescue_teams;
CREATE POLICY "Rescue teams manage policy"
    ON public.rescue_teams FOR ALL
    TO authenticated
    USING (public.is_super_admin(auth.uid()))
    WITH CHECK (public.is_super_admin(auth.uid()));

-- 5. RLS POLICIES FOR RELAY LOGS (HARDENED: ZERO ANONYMOUS ACCESS)
ALTER TABLE public.relay_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Allow insert relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Insert relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Relay logs insert policy" ON public.relay_logs;
DROP POLICY IF EXISTS "Relay logs all policy" ON public.relay_logs;

DROP POLICY IF EXISTS "Relay logs select policy" ON public.relay_logs;
CREATE POLICY "Relay logs select policy"
    ON public.relay_logs FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()));

-- 6. RLS POLICIES FOR EMERGENCY UPDATES
ALTER TABLE public.emergency_updates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read emergency updates" ON public.emergency_updates;
DROP POLICY IF EXISTS "Emergency updates select policy" ON public.emergency_updates;
CREATE POLICY "Emergency updates select policy"
    ON public.emergency_updates FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()));

DROP POLICY IF EXISTS "Allow insert emergency updates" ON public.emergency_updates;
DROP POLICY IF EXISTS "Emergency updates insert policy" ON public.emergency_updates;
CREATE POLICY "Emergency updates insert policy"
    ON public.emergency_updates FOR INSERT
    TO authenticated
    WITH CHECK (
        emergency_id IS NOT NULL 
        AND note IS NOT NULL
        AND (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()))
        AND updated_by_user_id = auth.uid()
    );

-- 7. RLS POLICIES FOR PROFILES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow read profiles" ON public.profiles;
DROP POLICY IF EXISTS "Profiles select policy" ON public.profiles;
CREATE POLICY "Profiles select policy"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR id = auth.uid());

DROP POLICY IF EXISTS "Allow insert profiles" ON public.profiles;
DROP POLICY IF EXISTS "Profiles insert policy" ON public.profiles;
CREATE POLICY "Profiles insert policy"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (public.is_super_admin(auth.uid()) OR id = auth.uid());

DROP POLICY IF EXISTS "Allow update profiles" ON public.profiles;
DROP POLICY IF EXISTS "Profiles update policy" ON public.profiles;
CREATE POLICY "Profiles update policy"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR id = auth.uid())
    WITH CHECK (public.is_super_admin(auth.uid()) OR id = auth.uid());

-- 8. ATOMIC OPERATOR STATUS UPDATE RPC FUNCTION (search_path secured)
CREATE OR REPLACE FUNCTION public.update_emergency_status_operator(
    p_emergency_id UUID,
    p_new_status public.emergency_status_enum,
    p_note TEXT DEFAULT NULL,
    p_assigned_team_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_updated_at TIMESTAMPTZ := pg_catalog.now();
    v_operator_id UUID := auth.uid();
    v_emergency_code TEXT;
BEGIN
    IF NOT (public.is_active_operator(v_operator_id) OR public.is_super_admin(v_operator_id)) THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Access Denied: Only active operators can update emergency status.');
    END IF;

    SELECT emergency_code INTO v_emergency_code 
    FROM public.emergencies 
    WHERE id = p_emergency_id;
    
    IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Emergency record not found');
    END IF;

    UPDATE public.emergencies
    SET status = p_new_status,
        assigned_team_id = COALESCE(p_assigned_team_id, assigned_team_id),
        acknowledged_at = CASE WHEN p_new_status = 'ACKNOWLEDGED' THEN v_updated_at ELSE acknowledged_at END,
        resolved_at = CASE WHEN p_new_status = 'RESOLVED' THEN v_updated_at ELSE resolved_at END,
        updated_at = v_updated_at
    WHERE id = p_emergency_id;

    INSERT INTO public.emergency_updates (
        emergency_id,
        new_status,
        note,
        updated_by_user_id
    ) VALUES (
        p_emergency_id,
        p_new_status,
        COALESCE(p_note, 'Status updated to ' || p_new_status::text || ' by Rescue Command'),
        v_operator_id
    );

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'log_audit_event' AND pronamespace = 'public'::regnamespace) THEN
        PERFORM public.log_audit_event(
            CASE 
                WHEN p_new_status = 'ACKNOWLEDGED' THEN 'SOS_ACCEPTED'
                WHEN p_new_status = 'RESOLVED' THEN 'EMERGENCY_RESOLVED'
                WHEN p_assigned_team_id IS NOT NULL THEN 'EMERGENCY_ASSIGNED'
                ELSE 'STATUS_CHANGED'
            END,
            'EMERGENCY',
            v_emergency_code,
            pg_catalog.jsonb_build_object('new_status', p_new_status, 'emergency_id', p_emergency_id, 'note', p_note)
        );
    END IF;

    RETURN pg_catalog.jsonb_build_object('success', true, 'status', p_new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.update_emergency_status_operator(UUID, public.emergency_status_enum, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_emergency_status_operator(UUID, public.emergency_status_enum, TEXT, UUID) TO authenticated, service_role;

-- 9. INITIALIZE RESCUE TEAMS (If none exist yet)
INSERT INTO public.rescue_teams (team_name, jurisdiction_zone, contact_phone, status, latitude, longitude)
SELECT 'Alpha Command Quick Response', 'Sector 1 - North District', '+91 98801 11223', 'ACTIVE', 12.9141, 74.8560
WHERE NOT EXISTS (SELECT 1 FROM public.rescue_teams WHERE team_name = 'Alpha Command Quick Response');

INSERT INTO public.rescue_teams (team_name, jurisdiction_zone, contact_phone, status, latitude, longitude)
SELECT 'Bravo Medical Rapid Response', 'Sector 2 - Coastal Belt', '+91 98802 22334', 'ACTIVE', 12.9280, 74.8420
WHERE NOT EXISTS (SELECT 1 FROM public.rescue_teams WHERE team_name = 'Bravo Medical Rapid Response');

INSERT INTO public.rescue_teams (team_name, jurisdiction_zone, contact_phone, status, latitude, longitude)
SELECT 'Delta Search & Evacuation', 'Sector 3 - High Risk Zone', '+91 98803 33445', 'STANDBY', 12.8950, 74.8650
WHERE NOT EXISTS (SELECT 1 FROM public.rescue_teams WHERE team_name = 'Delta Search & Evacuation');

-- 10. SECURE REALTIME REPLICATION REGISTRATION
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'emergencies'
    ) THEN 
        ALTER PUBLICATION supabase_realtime ADD TABLE public.emergencies; 
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'rescue_teams'
    ) THEN 
        ALTER PUBLICATION supabase_realtime ADD TABLE public.rescue_teams; 
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'relay_logs'
    ) THEN 
        ALTER PUBLICATION supabase_realtime ADD TABLE public.relay_logs; 
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'emergency_updates'
    ) THEN 
        ALTER PUBLICATION supabase_realtime ADD TABLE public.emergency_updates; 
    END IF;
END $$;
