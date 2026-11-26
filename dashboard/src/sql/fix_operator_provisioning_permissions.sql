-- ==============================================================================
-- SORYNTH RESCUE COMMAND - HARDENED OPERATOR PROVISIONING SECURITY HOTFIX
-- File: src/sql/fix_operator_provisioning_permissions.sql
-- Description: Hardens the admin_provision_operator_profile() RPC with:
--              1. Native PostgreSQL EXECUTE privilege restriction (service_role only).
--              2. Revoked EXECUTE from PUBLIC, anon, and authenticated.
--              3. Mandatory verified Super Admin actor validation (p_admin_user_id).
--              4. Least-privilege table grants (revokes DELETE on profiles & operator_profiles).
--              5. Atomic creation with immutable audit logging.
-- ==============================================================================
-- POSTGREST & SUPABASE SECURITY ARCHITECTURE:
-- In Supabase, PostgREST connects to PostgreSQL as 'authenticator' and executes
-- 'SET LOCAL ROLE service_role;' for service-role requests or 'SET LOCAL ROLE authenticated;'
-- for user requests.
--
-- Security is strictly enforced at the PostgreSQL permission layer:
-- - 'authenticated' has NO EXECUTE privilege on admin_provision_operator_profile().
--   PostgREST immediately blocks direct client RPC calls from citizens or operators.
-- - 'service_role' (used exclusively by the Edge Function) has EXECUTE privilege.
-- - Inside the Edge Function, caller JWT and active Super Admin status are verified
--   before the RPC is invoked, passing callerUser.id as p_admin_user_id.
-- - The RPC verifies p_admin_user_id via public.is_super_admin() for defense-in-depth.
-- ==============================================================================

-- 1. PRE-FLIGHT SCHEMA VERIFICATION
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'profiles'
    ) THEN
        RAISE EXCEPTION 'Pre-flight Failure: public.profiles table does not exist.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'operator_profiles'
    ) THEN
        RAISE EXCEPTION 'Pre-flight Failure: public.operator_profiles table does not exist.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'is_super_admin'
    ) THEN
        RAISE EXCEPTION 'Pre-flight Failure: public.is_super_admin function does not exist.';
    END IF;

    RAISE NOTICE 'Pre-flight Check PASSED: Required schema components verified.';
END $$;

-- 2. LEAST-PRIVILEGE TABLE GRANTS FOR SERVICE_ROLE
-- Ensure service_role has necessary operational access while strictly revoking
-- DELETE privileges to prevent accidental table truncation or citizen profile data loss.
GRANT SELECT, INSERT, UPDATE ON public.profiles TO service_role;
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.profiles FROM service_role;

GRANT SELECT, INSERT, UPDATE ON public.operator_profiles TO service_role;
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.operator_profiles FROM service_role;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'audit_logs'
    ) THEN
        REVOKE ALL PRIVILEGES ON public.audit_logs FROM service_role;
        EXECUTE 'GRANT SELECT, INSERT ON public.audit_logs TO service_role';
    END IF;
END $$;

-- 3. DROP OBSOLETE/INSECURE OVERLOADS IF PRESENT
DROP FUNCTION IF EXISTS public.admin_provision_operator_profile(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

-- 4. HARDENED ATOMIC OPERATOR PROVISIONING RPC (SECURITY DEFINER, search_path = '')
CREATE OR REPLACE FUNCTION public.admin_provision_operator_profile(
    p_admin_user_id UUID,
    p_user_id UUID,
    p_employee_id TEXT,
    p_full_name TEXT,
    p_email TEXT,
    p_phone_number TEXT DEFAULT NULL,
    p_rescue_role TEXT DEFAULT 'DISPATCHER',
    p_status TEXT DEFAULT 'active'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_clean_emp_id TEXT;
    v_clean_email TEXT;
    v_clean_status TEXT;
    v_valid_role public.rescue_role_enum;
BEGIN
    -- 1. Verify p_admin_user_id parameter is provided
    IF p_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'Security Policy Violation: p_admin_user_id cannot be null. Operator provisioning requires an authenticated Super Admin actor.';
    END IF;

    -- 2. Verify that p_admin_user_id is a verified, active Super Administrator in public.operator_profiles
    IF NOT public.is_super_admin(p_admin_user_id) THEN
        RAISE EXCEPTION 'Access Denied: The actor specified (UUID %) is not an active Super Administrator.', p_admin_user_id;
    END IF;

    -- 3. Parameter Validations
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'Missing parameter: p_user_id cannot be null.';
    END IF;

    v_clean_emp_id := UPPER(TRIM(p_employee_id));
    IF v_clean_emp_id IS NULL OR v_clean_emp_id = '' THEN
        RAISE EXCEPTION 'Missing parameter: p_employee_id cannot be empty.';
    END IF;

    v_clean_email := LOWER(TRIM(p_email));
    IF v_clean_email IS NULL OR v_clean_email = '' THEN
        RAISE EXCEPTION 'Missing parameter: p_email cannot be empty.';
    END IF;

    -- Prevent overriding or reusing root Super Admin email
    IF v_clean_email = 'admin@sorynth.org' THEN
        RAISE EXCEPTION 'Access Denied: Cannot provision an operator profile for the primary Super Admin email.';
    END IF;

    -- Ensure employee_id is not already taken by another user
    IF EXISTS (
        SELECT 1 FROM public.operator_profiles 
        WHERE employee_id = v_clean_emp_id AND user_id != p_user_id
    ) THEN
        RAISE EXCEPTION 'Conflict: Employee ID % is already assigned to another operator profile.', v_clean_emp_id;
    END IF;

    v_clean_status := LOWER(TRIM(COALESCE(p_status, 'active')));
    IF v_clean_status NOT IN ('active', 'inactive', 'suspended') THEN
        v_clean_status := 'active';
    END IF;

    -- Safely convert rescue_role text to enum
    BEGIN
        v_valid_role := UPPER(TRIM(p_rescue_role))::public.rescue_role_enum;
    EXCEPTION WHEN OTHERS THEN
        v_valid_role := 'DISPATCHER'::public.rescue_role_enum;
    END;

    -- 4. Upsert public.profiles (Universal Identity Directory: id, full_name, email, phone_number, rescue_role, updated_at)
    INSERT INTO public.profiles (
        id,
        full_name,
        email,
        phone_number,
        rescue_role,
        updated_at
    ) VALUES (
        p_user_id,
        TRIM(p_full_name),
        v_clean_email,
        NULLIF(TRIM(p_phone_number), ''),
        v_valid_role,
        pg_catalog.now()
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        email = EXCLUDED.email,
        phone_number = EXCLUDED.phone_number,
        rescue_role = EXCLUDED.rescue_role,
        updated_at = pg_catalog.now();

    -- 5. Upsert public.operator_profiles (Clearance Ledger: user_id, employee_id, full_name, email, role, status, created_at)
    INSERT INTO public.operator_profiles (
        user_id,
        employee_id,
        full_name,
        email,
        role,
        status,
        created_at
    ) VALUES (
        p_user_id,
        v_clean_emp_id,
        TRIM(p_full_name),
        v_clean_email,
        'operator',
        v_clean_status,
        pg_catalog.now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        employee_id = EXCLUDED.employee_id,
        full_name = EXCLUDED.full_name,
        email = EXCLUDED.email,
        role = 'operator',
        status = EXCLUDED.status;

    -- 6. Record Audit Log event
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'audit_logs'
    ) THEN
        INSERT INTO public.audit_logs (
            actor_id,
            actor_email,
            actor_name,
            actor_role,
            action,
            entity_type,
            entity_id,
            details,
            created_at
        ) VALUES (
            p_admin_user_id,
            (SELECT email FROM auth.users WHERE id = p_admin_user_id),
            'Super Administrator',
            'SUPER_ADMIN',
            'OPERATOR_CREATED',
            'OPERATOR',
            v_clean_emp_id,
            pg_catalog.jsonb_build_object(
                'operator_user_id', p_user_id,
                'employee_id', v_clean_emp_id,
                'full_name', TRIM(p_full_name),
                'email', v_clean_email,
                'rescue_role', v_valid_role::text,
                'status', v_clean_status,
                'provisioned_by_admin', p_admin_user_id,
                'timestamp', pg_catalog.now()
            ),
            pg_catalog.now()
        );
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'employee_id', v_clean_emp_id,
        'email', v_clean_email,
        'status', v_clean_status,
        'provisioned_by_admin', p_admin_user_id
    );
END;
$$;

-- 5. FUNCTION EXECUTION RESTRICTION (SERVICE_ROLE ONLY)
-- Explicitly revokes execution from PUBLIC, anon, and authenticated users.
-- Only trusted backend Edge Functions running with service_role can execute this function.
REVOKE ALL ON FUNCTION public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- 6. POST-MIGRATION PERMISSION VERIFICATION QUERY (READ-ONLY)
SELECT 
    'public.profiles' AS target_resource,
    has_table_privilege('service_role', 'public.profiles', 'SELECT') AS select_permitted,
    has_table_privilege('service_role', 'public.profiles', 'INSERT') AS direct_insert_permitted,
    has_table_privilege('service_role', 'public.profiles', 'DELETE') AS direct_delete_permitted,
    has_table_privilege('authenticated', 'public.profiles', 'DELETE') AS citizen_delete_permitted
UNION ALL
SELECT 
    'public.operator_profiles' AS target_resource,
    has_table_privilege('service_role', 'public.operator_profiles', 'SELECT') AS select_permitted,
    has_table_privilege('service_role', 'public.operator_profiles', 'UPDATE') AS direct_insert_permitted,
    has_table_privilege('service_role', 'public.operator_profiles', 'DELETE') AS direct_delete_permitted,
    has_table_privilege('authenticated', 'public.operator_profiles', 'DELETE') AS citizen_delete_permitted
UNION ALL
SELECT
    'admin_provision_operator_profile()' AS target_resource,
    has_function_privilege('service_role', 'public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)', 'EXECUTE') AS select_permitted,
    has_function_privilege('authenticated', 'public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)', 'EXECUTE') AS direct_insert_permitted,
    has_function_privilege('anon', 'public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)', 'EXECUTE') AS direct_delete_permitted,
    false AS citizen_delete_permitted;
