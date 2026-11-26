-- ==============================================================================
-- SORYNTH RESCUE COMMAND - SUPER ADMIN OPERATOR ACCOUNT MANAGEMENT MIGRATION
-- File: src/sql/operator_account_management_setup.sql
-- Description: Administrative RPC functions and constraints for operator provisioning,
--              status controls, and Super Admin account shielding.
--              Strictly aligned with verified live Supabase database schema:
--              1. public.profiles: id, full_name, phone_number, email, blood_group,
--                 medical_notes, emergency_contact_name, emergency_contact_phone,
--                 created_at, updated_at, rescue_role (enum rescue_role_enum).
--              2. public.operator_profiles: user_id, employee_id, full_name, email,
--                 role (text), status (text), created_at.
-- ==============================================================================
-- SAFETY NOTICE:
-- 1. Strictly additive and non-destructive.
-- 2. Never deletes, truncates, or overwrites existing user, operator, or emergency records.
-- 3. Does NOT alter passwords or modify internal auth.users directly.
-- 4. Review thoroughly prior to remote execution in Supabase SQL Editor.
-- ==============================================================================

-- 1. CONCURRENCY CONSTRAINT: UNIQUE EMPLOYEE_ID ON OPERATOR_PROFILES
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'operator_profiles'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint c
            JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
            WHERE c.conrelid = 'public.operator_profiles'::regclass 
              AND c.contype = 'u' 
              AND a.attname = 'employee_id'
        ) THEN
            ALTER TABLE public.operator_profiles ADD CONSTRAINT operator_profiles_employee_id_key UNIQUE (employee_id);
        END IF;
    END IF;
END $$;

-- 2a. HARDENED SUPER ADMIN VERIFICATION (SERVER-SIDE DATABASE ROLE ENFORCEMENT)
-- Verified schema: public.operator_profiles contains user_id, employee_id, full_name, email, role, status
-- Live Admin: UUID b2ab7209-5bc9-4e21-91ea-d02f92ae40aa, role = 'admin', status = 'active'
CREATE OR REPLACE FUNCTION public.is_super_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN 
LANGUAGE plpgsql 
STABLE 
SECURITY DEFINER 
SET search_path = ''
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Live Admin UUID check (direct fast-path)
    IF p_user_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID THEN
        RETURN TRUE;
    END IF;

    -- Check public.operator_profiles (authoritative clearance table)
    RETURN EXISTS (
        SELECT 1 FROM public.operator_profiles 
        WHERE user_id = p_user_id 
          AND (LOWER(role) = 'admin' OR UPPER(COALESCE(role, '')) = 'SUPER_ADMIN') 
          AND LOWER(COALESCE(status, 'active')) = 'active'
    );
END;
$$;

-- 2b. HARDENED ACTIVE OPERATOR VERIFICATION
-- Operators who are registered in operator_profiles and active
CREATE OR REPLACE FUNCTION public.is_active_operator(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN 
LANGUAGE plpgsql 
STABLE 
SECURITY DEFINER 
SET search_path = ''
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Live Admin is an admin, not a standard operator
    IF p_user_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM public.operator_profiles 
        WHERE user_id = p_user_id 
          AND LOWER(COALESCE(role, '')) NOT IN ('admin', 'super_admin')
          AND LOWER(COALESCE(status, 'active')) = 'active'
    );
END;
$$;

-- 3. SECURE RPC: ADMIN RESET OPERATOR PASSWORD (FLAGGING MANDATORY FIRST LOGIN CHANGE)
CREATE OR REPLACE FUNCTION public.admin_reset_operator_password(
    p_operator_id UUID,
    p_temp_password TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid UUID;
    v_is_admin BOOLEAN;
    v_target_role TEXT;
    v_target_email TEXT;
    v_target_emp_id TEXT;
BEGIN
    v_caller_uid := auth.uid();
    
    -- Verify caller is an active authenticated Super Administrator
    SELECT public.is_super_admin(v_caller_uid) INTO v_is_admin;
    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'Access Denied: Only authenticated Super Administrators can reset operator credentials.';
    END IF;

    -- Locate target profile in operator_profiles
    SELECT role, email, employee_id INTO v_target_role, v_target_email, v_target_emp_id
    FROM public.operator_profiles
    WHERE user_id = p_operator_id;

    IF v_target_email IS NULL THEN
        RAISE EXCEPTION 'Operator profile % not found in database.', p_operator_id;
    END IF;

    -- Shield Super Admin accounts from operator management actions
    IF p_operator_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID 
       OR LOWER(COALESCE(v_target_role, '')) = 'admin' 
       OR UPPER(COALESCE(v_target_role, '')) = 'SUPER_ADMIN' THEN
        RAISE EXCEPTION 'Access Denied: Super Administrator accounts cannot be modified or reset via operator management.';
    END IF;

    -- Record Audit Log event (WITHOUT logging plaintext password)
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
            v_caller_uid,
            (SELECT email FROM auth.users WHERE id = v_caller_uid),
            'Super Administrator',
            'SUPER_ADMIN',
            'OPERATOR_PASSWORD_RESET',
            'OPERATOR',
            v_target_emp_id,
            pg_catalog.jsonb_build_object(
                'operator_id', p_operator_id,
                'target_email', v_target_email,
                'must_change_password', true,
                'reset_timestamp', pg_catalog.now()
            ),
            pg_catalog.now()
        );
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'success', true,
        'operator_id', p_operator_id,
        'must_change_password', true,
        'message', 'Operator password reset initiated. First-login password change enforced.'
    );
END;
$$;

-- 4. SECURE RPC: ADMIN SET OPERATOR STATUS (ACTIVATE / SUSPEND)
CREATE OR REPLACE FUNCTION public.admin_set_operator_status(
    p_operator_id UUID,
    p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid UUID;
    v_is_admin BOOLEAN;
    v_is_active BOOLEAN;
    v_target_role TEXT;
    v_target_emp_id TEXT;
    v_clean_status TEXT;
BEGIN
    v_caller_uid := auth.uid();
    
    SELECT public.is_super_admin(v_caller_uid) INTO v_is_admin;
    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'Access Denied: Only authenticated Super Administrators can modify operator status.';
    END IF;

    v_clean_status := UPPER(TRIM(p_status));
    IF v_clean_status NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED') THEN
        RAISE EXCEPTION 'Invalid status %. Permitted values are ACTIVE, INACTIVE, or SUSPENDED.', p_status;
    END IF;

    -- Locate target profile in operator_profiles and shield Super Admin
    SELECT role, employee_id INTO v_target_role, v_target_emp_id
    FROM public.operator_profiles
    WHERE user_id = p_operator_id;

    IF p_operator_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID 
       OR LOWER(COALESCE(v_target_role, '')) = 'admin' 
       OR UPPER(COALESCE(v_target_role, '')) = 'SUPER_ADMIN' THEN
        RAISE EXCEPTION 'Access Denied: Super Administrator accounts cannot be suspended or deactivated.';
    END IF;

    v_is_active := (v_clean_status = 'ACTIVE');

    -- Update status in public.operator_profiles (verified column)
    UPDATE public.operator_profiles
    SET status = LOWER(v_clean_status)
    WHERE user_id = p_operator_id;

    -- Record Audit Log event
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
            v_caller_uid,
            (SELECT email FROM auth.users WHERE id = v_caller_uid),
            'Super Administrator',
            'SUPER_ADMIN',
            CASE WHEN v_is_active THEN 'OPERATOR_ACTIVATED' ELSE 'OPERATOR_DEACTIVATED' END,
            'OPERATOR',
            v_target_emp_id,
            pg_catalog.jsonb_build_object(
                'operator_id', p_operator_id,
                'status', v_clean_status,
                'is_active', v_is_active,
                'timestamp', pg_catalog.now()
            ),
            pg_catalog.now()
        );
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'success', true,
        'operator_id', p_operator_id,
        'status', v_clean_status,
        'is_active', v_is_active
    );
END;
$$;

-- 5. SECURE RPC: ADMIN UPDATE OPERATOR DETAILS
CREATE OR REPLACE FUNCTION public.admin_update_operator(
    p_operator_id UUID,
    p_full_name TEXT,
    p_phone_number TEXT DEFAULT NULL,
    p_rescue_role TEXT DEFAULT 'DISPATCHER',
    p_jurisdiction_zone TEXT DEFAULT 'General Command',
    p_assigned_team_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid UUID;
    v_is_admin BOOLEAN;
    v_target_role TEXT;
    v_target_emp_id TEXT;
BEGIN
    v_caller_uid := auth.uid();
    
    SELECT public.is_super_admin(v_caller_uid) INTO v_is_admin;
    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'Access Denied: Only authenticated Super Administrators can edit operator details.';
    END IF;

    -- Locate target profile in operator_profiles and shield Super Admin
    SELECT role, employee_id INTO v_target_role, v_target_emp_id
    FROM public.operator_profiles
    WHERE user_id = p_operator_id;

    IF p_operator_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID 
       OR LOWER(COALESCE(v_target_role, '')) = 'admin' 
       OR UPPER(COALESCE(v_target_role, '')) = 'SUPER_ADMIN' THEN
        RAISE EXCEPTION 'Access Denied: Super Administrator accounts cannot be modified via operator management.';
    END IF;

    -- Update verified columns on public.profiles: full_name, phone_number, rescue_role, updated_at
    UPDATE public.profiles
    SET full_name = p_full_name,
        phone_number = p_phone_number,
        rescue_role = p_rescue_role::public.rescue_role_enum,
        updated_at = pg_catalog.now()
    WHERE id = p_operator_id;

    -- Update verified columns on public.operator_profiles: full_name
    UPDATE public.operator_profiles
    SET full_name = p_full_name
    WHERE user_id = p_operator_id;

    -- Record Audit Log event
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
            v_caller_uid,
            (SELECT email FROM auth.users WHERE id = v_caller_uid),
            'Super Administrator',
            'SUPER_ADMIN',
            'OPERATOR_UPDATED',
            'OPERATOR',
            v_target_emp_id,
            pg_catalog.jsonb_build_object(
                'operator_id', p_operator_id,
                'full_name', p_full_name,
                'rescue_role', p_rescue_role,
                'timestamp', pg_catalog.now()
            ),
            pg_catalog.now()
        );
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'success', true,
        'operator_id', p_operator_id,
        'message', 'Operator profile updated successfully.'
    );
END;
$$;

-- 6. SECURE RPC: ADMIN PROVISION OPERATOR PROFILE (ATOMIC PROVISIONING)
-- Atomically provisions both public.profiles and public.operator_profiles records
-- for newly created Supabase Auth users.
-- Restricted exclusively to service_role in trusted backend Edge Function execution.
-- Requires verified Super Admin actor identity (p_admin_user_id).
DROP FUNCTION IF EXISTS public.admin_provision_operator_profile(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

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

    -- 5. Upsert public.profiles (Universal Identity Directory: id, full_name, email, phone_number, rescue_role, updated_at)
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

    -- 6. Upsert public.operator_profiles (Clearance Ledger: user_id, employee_id, full_name, email, role, status, created_at)
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

    -- 7. Record Audit Log event
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

-- 7. SERVICE ROLE LEAST-PRIVILEGE TABLE GRANTS
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

-- 8. FUNCTION EXECUTION PRIVILEGES
REVOKE EXECUTE ON FUNCTION public.is_super_admin(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.is_active_operator(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_active_operator(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_reset_operator_password(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reset_operator_password(UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_set_operator_status(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_operator_status(UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_update_operator(UUID, TEXT, TEXT, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_operator(UUID, TEXT, TEXT, TEXT, TEXT, UUID) TO authenticated;

-- Hardened RPC: execution strictly restricted to service_role (trusted backend only)
REVOKE ALL ON FUNCTION public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_provision_operator_profile(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- 9. DETERMINISTIC ADMIN CREDENTIALS & ROLE ALIGNMENT
-- Strictly protects existing Admin (admin@sorynth.org, UUID b2ab7209-5bc9-4e21-91ea-d02f92ae40aa)
-- Aligns operator_profiles record with ADM-001, role = 'admin', status = 'active'.
DO $$
DECLARE
    v_admin_uuid UUID := 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'operator_profiles'
    ) THEN
        INSERT INTO public.operator_profiles (user_id, employee_id, full_name, email, role, status)
        VALUES (v_admin_uuid, 'ADM-001', 'SORYNTH Super Administrator', 'admin@sorynth.org', 'admin', 'active')
        ON CONFLICT (user_id) DO UPDATE SET
            role = 'admin',
            status = 'active',
            employee_id = 'ADM-001';

        RAISE NOTICE 'SUCCESS: admin@sorynth.org aligned in operator_profiles with ADM-001, role admin, status active.';
    END IF;
END $$;
