-- ==============================================================================
-- SORYNTH RESCUE COMMAND & DISPATCH CONSOLE
-- HARDENED PRODUCTION POST-MIGRATION VERIFICATION SCRIPT (READ-ONLY)
-- File: src/sql/verify_post_migration_state.sql
-- ==============================================================================
-- GUARANTEES:
-- 1. Strictly READ-ONLY: Pure SELECT catalog inspection with zero DDL, DML, or state mutation.
-- 2. Fully compatible with Supabase SQL Editor, psql, and PgAdmin.
-- 3. Emits exactly 30 granular PASS / FAIL check rows:
--    Check 1.1: Core Tables Existence (8 required public tables, including lora_gateways)
--    Check 1.2: Critical Columns Verification (27 required columns)
--    Check 2.0: Row Level Security (RLS) Status (Active on all 8 tables)
--    Check 3.1: Preserved Citizen Policies (Exact 7 mobile app policies from migration baseline)
--    Check 3.2: Unmanaged Blanket-Permissive Policies Detection (0 permitted)
--    Check 4.0: Super Admin Profile Alignment (ADM-001, role admin, status active)
--    Check 5.1.01 - 5.1.16: Required Backend RPC Functions & Triggers (Exact identity signatures, prosecdef, search_path = '')
--    Check 5.2.01 - 5.2.03: Citizen Mobile SOS RPC Permissions (submit_sos_alert, cancel_emergency, get_emergency_status)
--    Check 5.3.00: Sanitization Trigger Security Mode (Strictly SECURITY INVOKER with search_path = '')
--    Check 6.0: Supabase Realtime Publication Tables (All 4 dispatch tables registered)
--    Check 7.1: relay_logs Table Grants Lockdown (Zero anon/PUBLIC, authenticated SELECT only)
--    Check 7.2: relay_logs RLS Policies (Zero anon policies, zero client INSERT policies)
--    Check 7.3: lora_gateways Security & Lockdown (Zero anon/PUBLIC grants, zero client writes)
-- ==============================================================================

WITH 
-- ------------------------------------------------------------------------------
-- 1.1 REQUIRED CORE TABLES EXISTENCE (1 CHECK ROW - 8 TABLES)
-- ------------------------------------------------------------------------------
required_tables_check AS (
    SELECT 
        '1.1.TABLES_EXISTENCE' AS check_id,
        'TABLES_COLUMNS' AS category,
        CASE 
            WHEN COUNT(t.table_name) = 8 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        'Found ' || COUNT(t.table_name) || ' of 8 required public tables' AS finding,
        'Present: ' || COALESCE(string_agg(req.table_name, ', ' ORDER BY req.table_name) FILTER (WHERE t.table_name IS NOT NULL), 'None') ||
        CASE 
            WHEN COUNT(t.table_name) < 8 THEN '; Missing: ' || COALESCE(string_agg(req.table_name, ', ' ORDER BY req.table_name) FILTER (WHERE t.table_name IS NULL), 'None')
            ELSE ''
        END AS details
    FROM (
        VALUES 
            ('profiles'), ('operator_profiles'), ('rescue_teams'),
            ('emergencies'), ('emergency_updates'), ('relay_logs'), 
            ('audit_logs'), ('lora_gateways')
    ) AS req(table_name)
    LEFT JOIN information_schema.tables t 
      ON t.table_schema = 'public' 
     AND t.table_name = req.table_name
),

-- ------------------------------------------------------------------------------
-- 1.2 CRITICAL COLUMNS VERIFICATION (1 CHECK ROW - 27 REQUIRED COLUMNS)
-- ------------------------------------------------------------------------------
required_columns_check AS (
    SELECT 
        '1.2.CRITICAL_COLUMNS' AS check_id,
        'TABLES_COLUMNS' AS category,
        CASE 
            WHEN COUNT(c.column_name) = 27 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        'Verified ' || COUNT(c.column_name) || ' of 27 critical columns across core tables' AS finding,
        CASE 
            WHEN COUNT(c.column_name) = 27 THEN 'All 27 critical columns present and verified in public schema'
            ELSE 'Missing columns: ' || COALESCE(string_agg(req.table_name || '.' || req.column_name, ', ' ORDER BY req.table_name, req.column_name) FILTER (WHERE c.column_name IS NULL), 'None')
        END AS details
    FROM (
        VALUES 
            ('profiles', 'id'), ('profiles', 'full_name'), ('profiles', 'rescue_role'),
            ('operator_profiles', 'user_id'), ('operator_profiles', 'employee_id'), 
            ('operator_profiles', 'role'), ('operator_profiles', 'status'),
            ('rescue_teams', 'id'), ('rescue_teams', 'team_name'), ('rescue_teams', 'status'),
            ('emergencies', 'id'), ('emergencies', 'emergency_code'), ('emergencies', 'status'),
            ('emergencies', 'is_guest'), ('emergencies', 'communication_method'),
            ('emergency_updates', 'id'), ('emergency_updates', 'emergency_id'), ('emergency_updates', 'new_status'),
            ('relay_logs', 'id'), ('relay_logs', 'emergency_id'), ('relay_logs', 'node_id'),
            ('audit_logs', 'id'), ('audit_logs', 'action'), ('audit_logs', 'entity_type'),
            ('lora_gateways', 'gateway_id'), ('lora_gateways', 'token_hash'), ('lora_gateways', 'status')
    ) AS req(table_name, column_name)
    LEFT JOIN information_schema.columns c 
      ON c.table_schema = 'public' 
     AND c.table_name = req.table_name 
     AND c.column_name = req.column_name
),

-- ------------------------------------------------------------------------------
-- 2.0 ROW LEVEL SECURITY (RLS) STATUS ACROSS ALL PUBLIC TABLES (1 CHECK ROW)
-- ------------------------------------------------------------------------------
rls_status_check AS (
    SELECT 
        '2.0.RLS_STATUS' AS check_id,
        'ROW_LEVEL_SECURITY' AS category,
        CASE 
            WHEN bool_and(c.relrowsecurity) = true AND COUNT(c.relname) = 8 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN bool_and(c.relrowsecurity) = true AND COUNT(c.relname) = 8 THEN 
                'Row Level Security is ACTIVE on all 8 core public tables'
            ELSE 'CRITICAL: One or more core tables lack active Row Level Security'
        END AS finding,
        COALESCE(string_agg(req.table_name || ': ' || CASE WHEN c.relrowsecurity THEN 'ACTIVE' ELSE 'DISABLED/MISSING' END, '; ' ORDER BY req.table_name), 'None') AS details
    FROM (
        VALUES 
            ('profiles'), ('operator_profiles'), ('rescue_teams'),
            ('emergencies'), ('emergency_updates'), ('relay_logs'), 
            ('audit_logs'), ('lora_gateways')
    ) AS req(table_name)
    LEFT JOIN pg_class c 
      ON c.relname = req.table_name 
     AND c.relnamespace = 'public'::regnamespace
),

-- ------------------------------------------------------------------------------
-- 3.1 EXACT PRESERVED CITIZEN POLICIES (1 CHECK ROW - 7 VERIFIED POLICIES)
-- ------------------------------------------------------------------------------
citizen_policies_check AS (
    SELECT 
        '3.1.CITIZEN_POLICIES' AS check_id,
        'POLICIES' AS category,
        CASE 
            WHEN COUNT(p.policyname) = 7 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        'Found ' || COUNT(p.policyname) || ' of 7 verified citizen mobile app policies preserved' AS finding,
        'Preserved: ' || COALESCE(string_agg(req.tablename || '.' || req.policyname, '; ' ORDER BY req.tablename, req.policyname) FILTER (WHERE p.policyname IS NOT NULL), 'None') ||
        CASE 
            WHEN COUNT(p.policyname) < 7 THEN '; Missing: ' || COALESCE(string_agg(req.tablename || '.' || req.policyname, '; ' ORDER BY req.tablename, req.policyname) FILTER (WHERE p.policyname IS NULL), 'None')
            ELSE ''
        END AS details
    FROM (
        VALUES 
            ('profiles', 'Users can view own profile'),
            ('profiles', 'Users can update own profile'),
            ('profiles', 'Users can insert own profile'),
            ('emergencies', 'Users can view their own emergencies'),
            ('emergencies', 'Users can update own emergencies'),
            ('emergencies', 'Authenticated users can create emergencies'),
            ('emergency_updates', 'Users can view updates for their own emergencies')
    ) AS req(tablename, policyname)
    LEFT JOIN pg_policies p 
      ON p.schemaname = 'public' 
     AND p.tablename = req.tablename 
     AND p.policyname = req.policyname
),

-- ------------------------------------------------------------------------------
-- 3.2 UNMANAGED BLANKET-PERMISSIVE POLICIES REMOVAL CHECK (1 CHECK ROW)
-- ------------------------------------------------------------------------------
blanket_permissive_policies_check AS (
    SELECT 
        '3.2.BLANKET_PERMISSIVE_POLICIES' AS check_id,
        'POLICIES' AS category,
        CASE 
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'Zero unmanaged blanket-permissive policies (qual/with_check = true) found'
            ELSE 'CRITICAL: Detected ' || COUNT(*) || ' unmanaged blanket-permissive policy/policies'
        END AS finding,
        COALESCE(string_agg(tablename || '.' || policyname || ' (' || cmd || ', roles: ' || array_to_string(roles, ', ') || ')', '; '), 'All clean') AS details
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('profiles', 'operator_profiles', 'rescue_teams', 'emergencies', 'emergency_updates', 'relay_logs', 'audit_logs', 'lora_gateways')
      AND (
          (roles && ARRAY['anon', 'public']::name[] OR roles IS NULL)
          AND (qual = 'true' OR with_check = 'true')
      )
),

-- ------------------------------------------------------------------------------
-- 4.0 SUPER ADMIN OPERATOR PROFILE ALIGNMENT (1 CHECK ROW)
-- ------------------------------------------------------------------------------
admin_profile_check AS (
    SELECT 
        '4.0.ADMIN_PROFILE' AS check_id,
        'ADMIN_ALIGNMENT' AS category,
        CASE 
            WHEN op.user_id IS NULL THEN 'FAIL'
            WHEN op.employee_id = 'ADM-001' 
                 AND lower(op.role) IN ('admin', 'super_admin') 
                 AND lower(op.status) = 'active' THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN op.user_id IS NULL THEN 'CRITICAL: Super Admin record missing in public.operator_profiles'
            WHEN op.employee_id = 'ADM-001' 
                 AND lower(op.role) IN ('admin', 'super_admin') 
                 AND lower(op.status) = 'active' THEN 
                'Super Admin (admin@sorynth.org) is verified: ADM-001, role admin, status active'
            ELSE 'CRITICAL: Super Admin account misconfigured in operator_profiles'
        END AS finding,
        CASE 
            WHEN op.user_id IS NULL THEN 'Missing record for UUID b2ab7209-5bc9-4e21-91ea-d02f92ae40aa or admin@sorynth.org'
            ELSE 'user_id: ' || op.user_id::text || ', employee_id: ' || COALESCE(op.employee_id, 'NULL') || ', role: ' || COALESCE(op.role, 'NULL') || ', status: ' || COALESCE(op.status, 'NULL')
        END AS details
    FROM (SELECT 1) dummy
    LEFT JOIN public.operator_profiles op 
      ON (op.user_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID OR lower(op.email) = 'admin@sorynth.org')
),

-- ------------------------------------------------------------------------------
-- 5.0 CATALOG INSPECTION OF EXISTING FUNCTIONS IN PUBLIC SCHEMA
-- ------------------------------------------------------------------------------
existing_public_functions AS (
    SELECT 
        p.oid,
        p.proname,
        p.prosecdef,
        format_type(p.prorettype, NULL) AS actual_rettype,
        regexp_replace(
            replace(pg_catalog.pg_get_function_identity_arguments(p.oid), 'public.', ''),
            '\s+', ' ', 'g'
        ) AS actual_identity_args,
        EXISTS (
            SELECT 1 
            FROM unnest(p.proconfig) cfg 
            WHERE cfg LIKE 'search_path=%' 
              AND btrim(substring(cfg from 13), '"'' ') = ''
        ) AS has_hardened_search_path,
        (
            SELECT cfg 
            FROM unnest(p.proconfig) cfg 
            WHERE cfg LIKE 'search_path=%' 
            LIMIT 1
        ) AS actual_search_path_setting
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
),

-- ------------------------------------------------------------------------------
-- 5.1 INDIVIDUAL VERIFICATION OF ALL 16 REQUIRED BACKEND RPCS & TRIGGERS (16 CHECK ROWS)
-- ------------------------------------------------------------------------------
individual_rpc_functions_check AS (
    SELECT 
        req.check_id,
        'FUNCTIONS_RPCS' AS category,
        CASE 
            WHEN f.oid IS NULL THEN 'FAIL'
            WHEN f.prosecdef = req.expected_secdef 
                 AND f.actual_rettype = req.expected_rettype 
                 AND f.has_hardened_search_path THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN f.oid IS NULL THEN 
                'CRITICAL: Function public.' || req.proname || '(' || req.expected_identity_args || ') is MISSING'
            WHEN f.prosecdef = req.expected_secdef 
                 AND f.actual_rettype = req.expected_rettype 
                 AND f.has_hardened_search_path THEN 
                'Function public.' || req.proname || '(' || req.expected_identity_args || ') verified'
            ELSE 
                'CRITICAL: Function public.' || req.proname || '(' || req.expected_identity_args || ') configuration mismatch'
        END AS finding,
        CASE 
            WHEN f.oid IS NULL THEN 
                'Not found in public schema. Expected: (' || req.expected_identity_args || ') -> ' || req.expected_rettype || 
                ', SEC_DEF: ' || req.expected_secdef::text || ', search_path: ""'
            WHEN f.prosecdef = req.expected_secdef 
                 AND f.actual_rettype = req.expected_rettype 
                 AND f.has_hardened_search_path THEN 
                'SECURITY DEFINER: ' || f.prosecdef::text || ', return_type: ' || f.actual_rettype || 
                ', search_path: ' || COALESCE(f.actual_search_path_setting, '""')
            ELSE 
                TRIM(TRAILING '; ' FROM 
                    CASE WHEN f.prosecdef != req.expected_secdef THEN 'Security mode mismatch: expected ' || req.expected_secdef::text || ', found ' || f.prosecdef::text || '; ' ELSE '' END ||
                    CASE WHEN f.actual_rettype != req.expected_rettype THEN 'Return type mismatch: expected ' || req.expected_rettype || ', found ' || f.actual_rettype || '; ' ELSE '' END ||
                    CASE WHEN NOT f.has_hardened_search_path THEN 'Search path mismatch: expected exact hardened search_path = '''', found: ' || COALESCE(f.actual_search_path_setting, 'UNSET') || '; ' ELSE '' END
                )
        END AS details
    FROM (
        VALUES 
            ('5.1.01.FUNC_is_super_admin', 'is_super_admin', 'p_user_id uuid', true, 'boolean'),
            ('5.1.02.FUNC_is_active_operator', 'is_active_operator', 'p_user_id uuid', true, 'boolean'),
            ('5.1.03.FUNC_generate_employee_id', 'generate_employee_id', '', true, 'text'),
            ('5.1.04.FUNC_log_audit_event', 'log_audit_event', 'p_action text, p_entity_type text, p_entity_id text, p_details jsonb, p_actor_id uuid', true, 'uuid'),
            ('5.1.05.FUNC_operator_set_team_readiness', 'operator_set_team_readiness', 'p_team_id uuid, p_status text', true, 'jsonb'),
            ('5.1.06.FUNC_update_emergency_status_operator', 'update_emergency_status_operator', 'p_emergency_id uuid, p_new_status emergency_status_enum, p_note text, p_assigned_team_id uuid', true, 'jsonb'),
            ('5.1.07.FUNC_admin_reset_operator_password', 'admin_reset_operator_password', 'p_operator_id uuid, p_temp_password text', true, 'jsonb'),
            ('5.1.08.FUNC_admin_set_operator_status', 'admin_set_operator_status', 'p_operator_id uuid, p_status text', true, 'jsonb'),
            ('5.1.09.FUNC_admin_update_operator', 'admin_update_operator', 'p_operator_id uuid, p_full_name text, p_phone_number text, p_rescue_role text, p_jurisdiction_zone text, p_assigned_team_id uuid', true, 'jsonb'),
            ('5.1.10.FUNC_ingest_lora_relay_packet', 'ingest_lora_relay_packet', 'p_emergency_id uuid, p_node_id character varying, p_gateway_id character varying, p_gateway_token text, p_rssi integer, p_snr double precision, p_hop_number integer, p_payload_raw text', true, 'jsonb'),
            ('5.1.11.TRIG_prevent_operator_privilege_escalation', 'prevent_operator_privilege_escalation', '', true, 'trigger'),
            ('5.1.12.TRIG_prevent_operator_profile_tampering', 'prevent_operator_profile_tampering', '', true, 'trigger'),
            ('5.1.13.TRIG_prevent_operator_emergency_tampering', 'prevent_operator_emergency_tampering', '', true, 'trigger'),
            ('5.1.14.FUNC_admin_register_lora_gateway', 'admin_register_lora_gateway', 'p_gateway_id character varying, p_gateway_name text, p_plaintext_token text, p_notes text', true, 'jsonb'),
            ('5.1.15.FUNC_admin_set_lora_gateway_status', 'admin_set_lora_gateway_status', 'p_gateway_id character varying, p_status text', true, 'jsonb'),
            ('5.1.16.FUNC_admin_rotate_lora_gateway_token', 'admin_rotate_lora_gateway_token', 'p_gateway_id character varying, p_new_plaintext_token text', true, 'jsonb')
    ) AS req(check_id, proname, expected_identity_args, expected_secdef, expected_rettype)
    LEFT JOIN existing_public_functions f
      ON f.proname = req.proname 
     AND f.actual_identity_args = req.expected_identity_args
),

-- ------------------------------------------------------------------------------
-- 5.2 INDIVIDUAL CITIZEN MOBILE SOS RPC PERMISSIONS (3 CHECK ROWS)
-- ------------------------------------------------------------------------------
individual_citizen_rpc_check AS (
    SELECT 
        req.check_id,
        'FUNCTIONS_RPCS' AS category,
        CASE 
            WHEN f.oid IS NULL THEN 'FAIL'
            WHEN f.actual_rettype = 'jsonb' 
                 AND f.has_anon_execute 
                 AND f.has_auth_execute THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN f.oid IS NULL THEN 
                'CRITICAL: Citizen SOS RPC public.' || req.proname || '(' || req.expected_identity_args || ') is MISSING'
            WHEN f.actual_rettype = 'jsonb' 
                 AND f.has_anon_execute 
                 AND f.has_auth_execute THEN 
                'Citizen SOS RPC public.' || req.proname || ' verified with required anon & authenticated EXECUTE grants'
            ELSE 
                'CRITICAL: Citizen SOS RPC public.' || req.proname || ' configuration or grant mismatch'
        END AS finding,
        CASE 
            WHEN f.oid IS NULL THEN 
                'Function not found in public schema with expected identity arguments: (' || req.expected_identity_args || ')'
            WHEN f.actual_rettype = 'jsonb' 
                 AND f.has_anon_execute 
                 AND f.has_auth_execute THEN 
                'Signature: OK, return_type: jsonb (OK), anon EXECUTE: granted, authenticated EXECUTE: granted'
            ELSE 
                TRIM(TRAILING '; ' FROM 
                    CASE WHEN f.actual_rettype != 'jsonb' THEN 'Return type mismatch: expected jsonb, found ' || f.actual_rettype || '; ' ELSE '' END ||
                    CASE WHEN NOT f.has_anon_execute THEN 'Missing EXECUTE grant to anon; ' ELSE '' END ||
                    CASE WHEN NOT f.has_auth_execute THEN 'Missing EXECUTE grant to authenticated; ' ELSE '' END
                )
        END AS details
    FROM (
        VALUES 
            ('5.2.01.RPC_submit_sos_alert', 'submit_sos_alert', 'p_emergency_code character varying, p_sender_name text, p_sender_phone text, p_emergency_type text, p_custom_message text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_communication_method text, p_hop_count integer, p_relay_path text[]'),
            ('5.2.02.RPC_cancel_emergency', 'cancel_emergency', 'p_emergency_code character varying, p_reason text'),
            ('5.2.03.RPC_get_emergency_status', 'get_emergency_status', 'p_emergency_code character varying')
    ) AS req(check_id, proname, expected_identity_args)
    LEFT JOIN (
        SELECT 
            p.oid,
            p.proname,
            format_type(p.prorettype, NULL) AS actual_rettype,
            regexp_replace(
                replace(pg_catalog.pg_get_function_identity_arguments(p.oid), 'public.', ''),
                '\s+', ' ', 'g'
            ) AS actual_identity_args,
            has_function_privilege('anon', p.oid, 'EXECUTE') AS has_anon_execute,
            has_function_privilege('authenticated', p.oid, 'EXECUTE') AS has_auth_execute
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
    ) f ON f.proname = req.proname 
       AND f.actual_identity_args = req.expected_identity_args
),

-- ------------------------------------------------------------------------------
-- 5.3.00 SANITIZATION TRIGGER SECURITY INVOKER VERIFICATION (1 CHECK ROW)
-- ------------------------------------------------------------------------------
trigger_mode_check AS (
    SELECT 
        '5.3.00.TRIGGER_SECURITY_INVOKER' AS check_id,
        'FUNCTIONS_RPCS' AS category,
        CASE 
            WHEN p.oid IS NULL THEN 'FAIL'
            WHEN p.prosecdef = false 
                 AND p.actual_identity_args = '' 
                 AND p.actual_rettype = 'trigger'
                 AND p.has_hardened_search_path THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN p.oid IS NULL THEN 
                'CRITICAL: Trigger function public.sanitize_emergency_submission() is missing'
            WHEN p.prosecdef = false 
                 AND p.actual_identity_args = '' 
                 AND p.actual_rettype = 'trigger'
                 AND p.has_hardened_search_path THEN 
                'sanitize_emergency_submission is correctly declared SECURITY INVOKER with hardened search_path = '''''
            WHEN p.prosecdef = true THEN 
                'CRITICAL: sanitize_emergency_submission is declared SECURITY DEFINER (vulnerable to status spoofing)'
            WHEN NOT p.has_hardened_search_path THEN 
                'CRITICAL: sanitize_emergency_submission lacks exact hardened search_path = '''''
            ELSE 
                'CRITICAL: sanitize_emergency_submission configuration mismatch'
        END AS finding,
        CASE 
            WHEN p.oid IS NULL THEN 'Missing pg_proc entry for public.sanitize_emergency_submission()'
            ELSE 'Owner: ' || pg_get_userbyid(p.proowner) || 
                 ', prosecdef: ' || p.prosecdef::text || ' (expected false)' ||
                 ', search_path: ' || COALESCE(p.actual_search_path_setting, 'UNSET') || ' (expected "")' ||
                 ', return_type: ' || p.actual_rettype
        END AS details
    FROM (SELECT 1) dummy
    LEFT JOIN (
        SELECT 
            p.oid,
            p.proowner,
            p.prosecdef,
            format_type(p.prorettype, NULL) AS actual_rettype,
            regexp_replace(
                replace(pg_catalog.pg_get_function_identity_arguments(p.oid), 'public.', ''),
                '\s+', ' ', 'g'
            ) AS actual_identity_args,
            EXISTS (
                SELECT 1 
                FROM unnest(p.proconfig) cfg 
                WHERE cfg LIKE 'search_path=%' 
                  AND btrim(substring(cfg from 13), '"'' ') = ''
            ) AS has_hardened_search_path,
            (SELECT cfg FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%' LIMIT 1) AS actual_search_path_setting
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' 
          AND p.proname = 'sanitize_emergency_submission'
          AND format_type(p.prorettype, NULL) = 'trigger'
    ) p ON true
),

-- ------------------------------------------------------------------------------
-- 6.0 SUPABASE REALTIME PUBLICATION REGISTRATION (1 CHECK ROW - 4 DISPATCH TABLES)
-- ------------------------------------------------------------------------------
realtime_publication_check AS (
    SELECT 
        '6.0.REALTIME_PUBLICATION' AS check_id,
        'REALTIME' AS category,
        CASE 
            WHEN COUNT(p.tablename) = 4 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        'Found ' || COUNT(p.tablename) || ' of 4 required dispatch tables registered in supabase_realtime publication' AS finding,
        'Registered: ' || COALESCE(string_agg(req.tablename, ', ' ORDER BY req.tablename) FILTER (WHERE p.tablename IS NOT NULL), 'None') ||
        CASE 
            WHEN COUNT(p.tablename) < 4 THEN '; Missing: ' || COALESCE(string_agg(req.tablename, ', ' ORDER BY req.tablename) FILTER (WHERE p.tablename IS NULL), 'None')
            ELSE ''
        END AS details
    FROM (
        VALUES 
            ('emergencies'), ('rescue_teams'), ('relay_logs'), ('emergency_updates')
    ) AS req(tablename)
    LEFT JOIN pg_publication_tables p 
      ON p.pubname = 'supabase_realtime' 
     AND p.schemaname = 'public' 
     AND p.tablename = req.tablename
),

-- ------------------------------------------------------------------------------
-- 7.1 RELAY_LOGS TABLE PERMISSIONS LOCKDOWN (1 CHECK ROW)
-- ------------------------------------------------------------------------------
relay_logs_security_check AS (
    SELECT 
        '7.1.RELAY_LOGS_PRIVILEGES' AS check_id,
        'RELAY_LOGS_SECURITY' AS category,
        CASE 
            WHEN anon_public_count = 0 AND auth_has_select AND NOT auth_has_write THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN anon_public_count = 0 AND auth_has_select AND NOT auth_has_write THEN 
                'relay_logs table permissions: 0 privileges for anon/PUBLIC; authenticated has SELECT only'
            ELSE 'CRITICAL: relay_logs table permissions exposure detected'
        END AS finding,
        'anon/PUBLIC grants: ' || anon_public_count || ', authenticated SELECT: ' || auth_has_select || ', authenticated writes: ' || auth_has_write AS details
    FROM (
        SELECT 
            COUNT(*) FILTER (WHERE grantee IN ('anon', 'PUBLIC')) AS anon_public_count,
            bool_or(grantee = 'authenticated' AND privilege_type = 'SELECT') AS auth_has_select,
            bool_or(grantee = 'authenticated' AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')) AS auth_has_write
        FROM information_schema.role_table_grants
        WHERE table_schema = 'public' AND table_name = 'relay_logs'
    ) g
),

-- ------------------------------------------------------------------------------
-- 7.2 RELAY_LOGS POLICIES HARDENING (1 CHECK ROW - ZERO ANON / CLIENT WRITES)
-- ------------------------------------------------------------------------------
relay_logs_policies_check AS (
    SELECT 
        '7.2.RELAY_LOGS_POLICIES' AS check_id,
        'RELAY_LOGS_SECURITY' AS category,
        CASE 
            WHEN anon_policies = 0 AND insert_policies = 0 AND select_policies >= 1 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        'relay_logs policies: 0 anon policies, 0 direct client INSERT policies, hardened SELECT policy active' AS finding,
        'anon policies: ' || anon_policies || ', client insert policies: ' || insert_policies || ', select policies: ' || select_policies AS details
    FROM (
        SELECT 
            COUNT(*) FILTER (WHERE roles && ARRAY['anon', 'public']::name[] OR roles IS NULL) AS anon_policies,
            COUNT(*) FILTER (WHERE cmd = 'INSERT' AND NOT (roles = ARRAY['service_role']::name[])) AS insert_policies,
            COUNT(*) FILTER (WHERE cmd = 'SELECT' AND roles = ARRAY['authenticated']::name[]) AS select_policies
        FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'relay_logs'
    ) p
),

-- ------------------------------------------------------------------------------
-- 7.3 LORA_GATEWAYS REGISTRY SECURITY & PRIVILEGES (1 CHECK ROW)
-- ------------------------------------------------------------------------------
lora_gateways_security_check AS (
    SELECT 
        '7.3.LORA_GATEWAYS_SECURITY' AS check_id,
        'GATEWAY_REGISTRY_SECURITY' AS category,
        CASE 
            WHEN c.relname IS NULL THEN 'FAIL'
            WHEN c.relrowsecurity = true 
                 AND anon_public_count = 0 
                 AND auth_write_count = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN c.relname IS NULL THEN 'CRITICAL: public.lora_gateways table is missing'
            WHEN c.relrowsecurity = true 
                 AND anon_public_count = 0 
                 AND auth_write_count = 0 THEN 
                'lora_gateways registry secured: RLS active, zero anon/PUBLIC privileges, direct client writes blocked'
            WHEN c.relrowsecurity != true THEN 'CRITICAL: Row Level Security is DISABLED on public.lora_gateways'
            ELSE 'CRITICAL: lora_gateways table privileges exposure detected'
        END AS finding,
        CASE 
            WHEN c.relname IS NULL THEN 'Table not found in public schema'
            ELSE 'RLS: ' || c.relrowsecurity::text || ', anon/PUBLIC grants: ' || anon_public_count || ', authenticated writes: ' || auth_write_count
        END AS details
    FROM (SELECT 1) dummy
    LEFT JOIN pg_class c 
      ON c.relname = 'lora_gateways' 
     AND c.relnamespace = 'public'::regnamespace
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(*) FILTER (WHERE grantee IN ('anon', 'PUBLIC')) AS anon_public_count,
            COUNT(*) FILTER (WHERE grantee = 'authenticated' AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')) AS auth_write_count
        FROM information_schema.role_table_grants
        WHERE table_schema = 'public' AND table_name = 'lora_gateways'
    ) g ON true
)

-- ------------------------------------------------------------------------------
-- FINAL COMBINED VERIFICATION REPORT (EXACTLY 30 GRANULAR RESULT ROWS)
-- ------------------------------------------------------------------------------
SELECT 
    check_id,
    category,
    status,
    finding,
    details
FROM (
    SELECT * FROM required_tables_check
    UNION ALL
    SELECT * FROM required_columns_check
    UNION ALL
    SELECT * FROM rls_status_check
    UNION ALL
    SELECT * FROM citizen_policies_check
    UNION ALL
    SELECT * FROM blanket_permissive_policies_check
    UNION ALL
    SELECT * FROM admin_profile_check
    UNION ALL
    SELECT * FROM individual_rpc_functions_check
    UNION ALL
    SELECT * FROM individual_citizen_rpc_check
    UNION ALL
    SELECT * FROM trigger_mode_check
    UNION ALL
    SELECT * FROM realtime_publication_check
    UNION ALL
    SELECT * FROM relay_logs_security_check
    UNION ALL
    SELECT * FROM relay_logs_policies_check
    UNION ALL
    SELECT * FROM lora_gateways_security_check
) report
ORDER BY check_id;
