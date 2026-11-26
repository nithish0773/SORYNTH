-- =========================================================================
-- SORYNTH SECURE DATABASE MIGRATION: ADMIN DELETE OPERATOR
-- File: src/sql/admin_delete_operator_setup.sql
-- Description: Hardened Super Admin Permanent Operator Deletion
-- Ensures operational history (emergencies, logs, updates) is strictly preserved.
-- Only service_role and verified Super Admins can execute.
-- =========================================================================

-- 1. SECURE RPC: ADMIN DELETE OPERATOR
CREATE OR REPLACE FUNCTION public.admin_delete_operator(
    p_admin_user_id UUID,
    p_operator_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_target_role TEXT;
    v_target_email TEXT;
    v_target_emp_id TEXT;
    v_target_name TEXT;
    v_admin_email TEXT;
    v_admin_name TEXT;
BEGIN
    -- 1. Validate parameters
    IF p_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'Security Policy Violation: p_admin_user_id cannot be null. Operator deletion requires an authenticated Super Admin actor.';
    END IF;

    IF p_operator_id IS NULL THEN
        RAISE EXCEPTION 'Operator user_id is required for permanent deletion.';
    END IF;

    -- 2. Verify that p_admin_user_id is a verified, active Super Administrator in public.operator_profiles
    SELECT public.is_super_admin(p_admin_user_id) INTO v_is_admin;
    IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'Access Denied: The actor specified (%) is not a verified active Super Administrator.', p_admin_user_id;
    END IF;

    -- 3. Prevent self-deletion of currently authenticated administrator
    IF p_operator_id = p_admin_user_id THEN
        RAISE EXCEPTION 'Access Denied: You cannot delete your own active administrator account.';
    END IF;

    -- 4. Locate target profile in operator_profiles
    SELECT role, email, employee_id, full_name 
    INTO v_target_role, v_target_email, v_target_emp_id, v_target_name
    FROM public.operator_profiles
    WHERE user_id = p_operator_id;

    IF v_target_email IS NULL THEN
        -- Also check profiles table if operator_profiles row is absent
        SELECT full_name, email 
        INTO v_target_name, v_target_email
        FROM public.profiles
        WHERE id = p_operator_id;

        IF v_target_email IS NULL THEN
            RAISE EXCEPTION 'Operator profile % not found in database.', p_operator_id;
        END IF;
    END IF;

    -- 5. Shield Super Admin accounts from permanent deletion
    IF p_operator_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID 
       OR LOWER(COALESCE(v_target_role, '')) = 'admin' 
       OR UPPER(COALESCE(v_target_role, '')) = 'SUPER_ADMIN'
       OR LOWER(COALESCE(v_target_email, '')) = 'admin@sorynth.org' THEN
        RAISE EXCEPTION 'Access Denied: Super Administrator accounts cannot be deleted.';
    END IF;

    -- 6. PRESERVE OPERATIONAL HISTORY (Safely disassociate foreign key references)
    -- Disassociate emergency updates authored by this operator without deleting the update records
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'emergency_updates'
    ) THEN
        UPDATE public.emergency_updates
        SET updated_by_user_id = NULL
        WHERE updated_by_user_id = p_operator_id;
    END IF;

    -- Disassociate emergencies submitted or handled by this operator without deleting the incident
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'emergencies'
    ) THEN
        UPDATE public.emergencies
        SET user_id = NULL
        WHERE user_id = p_operator_id;
    END IF;

    -- 7. Safely delete operator clearance records from application tables
    DELETE FROM public.operator_profiles WHERE user_id = p_operator_id;
    DELETE FROM public.profiles WHERE id = p_operator_id;

    -- 8. Fetch admin email and full name for audit log
    SELECT email INTO v_admin_email 
    FROM auth.users 
    WHERE id = p_admin_user_id;

    SELECT full_name INTO v_admin_name
    FROM public.operator_profiles
    WHERE user_id = p_admin_user_id;

    IF v_admin_name IS NULL THEN
        SELECT full_name INTO v_admin_name
        FROM public.profiles
        WHERE id = p_admin_user_id;
    END IF;

    -- 9. Record immutable audit log
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
            v_admin_email,
            COALESCE(v_admin_name, 'Super Administrator'),
            'SUPER_ADMIN',
            'OPERATOR_DELETED',
            'OPERATOR',
            COALESCE(v_target_emp_id, p_operator_id::text),
            pg_catalog.jsonb_build_object(
                'operator_id', p_operator_id,
                'target_name', v_target_name,
                'target_email', v_target_email,
                'employee_id', v_target_emp_id,
                'deleted_by_admin', p_admin_user_id,
                'timestamp', pg_catalog.now()
            ),
            pg_catalog.now()
        );
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'success', true,
        'operator_id', p_operator_id,
        'employee_id', v_target_emp_id,
        'full_name', v_target_name,
        'message', 'Operator profile safely removed from application ledger. Operational history preserved.'
    );
END;
$$;

-- 2. LEAST-PRIVILEGE PERMISSION ASSIGNMENTS
REVOKE ALL ON FUNCTION public.admin_delete_operator(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_operator(UUID, UUID) TO service_role;
