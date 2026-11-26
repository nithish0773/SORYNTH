-- ==============================================================================
-- SORYNTH RESCUE COMMAND - READ-ONLY RELAY LOGS & GATEWAY SECURITY VERIFICATION
-- File: src/sql/verify_relay_logs_security.sql
-- Description: Purely diagnostic, non-mutating query to verify that
--              public.relay_logs is locked down against anonymous access and
--              direct client writes, while verifying the public.lora_gateways
--              registry table and associated Super Admin RPC security.
-- ==============================================================================
-- GUARANTEES:
-- 1. Strictly READ-ONLY: Pure SELECT inspection with zero DDL or DML mutations.
-- 2. Evaluates table grants, RLS status, policies, RPCs, and row count baselines.
-- ==============================================================================
-- INSTRUCTIONS:
-- Paste this entire script into your Supabase SQL Editor and click RUN.
-- Review the tabular report to verify all checks pass.
-- ==============================================================================

WITH 
-- 1. Check Table Privileges on public.relay_logs for anon and PUBLIC
privilege_anon_public AS (
    SELECT 
        '1. TABLE_PRIVILEGES_ANON_PUBLIC' AS check_name,
        CASE 
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'Zero privileges granted to anon and PUBLIC on public.relay_logs'
            ELSE 'CRITICAL: Found ' || COUNT(*) || ' active table privilege(s) granted to anon/PUBLIC: ' || string_agg(grantee || ':' || privilege_type, ', ')
        END AS details
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public' 
      AND table_name = 'relay_logs'
      AND grantee IN ('anon', 'PUBLIC')
),

-- 2. Check Table Privileges on public.relay_logs for authenticated
privilege_authenticated AS (
    SELECT 
        '2. TABLE_PRIVILEGES_AUTHENTICATED' AS check_name,
        CASE 
            WHEN COUNT(*) = 0 THEN 'WARNING: authenticated has no table privileges'
            WHEN bool_or(privilege_type = 'SELECT') AND NOT bool_or(privilege_type != 'SELECT') THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'WARNING: authenticated has no privileges (cannot view packet history)'
            WHEN bool_or(privilege_type = 'SELECT') AND NOT bool_or(privilege_type != 'SELECT') THEN 
                'authenticated role has strictly SELECT privilege on public.relay_logs (zero write/insert/truncate privileges)'
            ELSE 'CRITICAL: authenticated has unexpected privileges: ' || string_agg(DISTINCT privilege_type, ', ') || ' (Expected: SELECT only)'
        END AS details
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public' 
      AND table_name = 'relay_logs'
      AND grantee = 'authenticated'
),

-- 3. Check Row Level Security (RLS) Status on relay_logs
rls_status_check AS (
    SELECT 
        '3. RLS_ENABLED_RELAY_LOGS' AS check_name,
        CASE 
            WHEN c.relrowsecurity = true THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN c.relrowsecurity = true THEN 'Row Level Security is ACTIVE on public.relay_logs'
            ELSE 'CRITICAL: Row Level Security is DISABLED on public.relay_logs'
        END AS details
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'relay_logs'
),

-- 4. Check Anonymous Policies on relay_logs
anonymous_policies_check AS (
    SELECT 
        '4. ANONYMOUS_POLICIES_RELAY_LOGS' AS check_name,
        CASE 
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'Every policy on public.relay_logs inspected: zero policies target anon or PUBLIC'
            ELSE 'CRITICAL: Found ' || COUNT(*) || ' policy/policies on public.relay_logs targeting anon or PUBLIC: ' || string_agg(policyname || ' (' || cmd || ', roles: ' || array_to_string(roles, ', ') || ')', '; ')
        END AS details
    FROM pg_policies
    WHERE schemaname = 'public' 
      AND tablename = 'relay_logs'
      AND (
          'anon' = ANY(roles)
          OR 'public' = ANY(roles)
          OR roles && ARRAY['anon', 'public']::name[]
          OR roles IS NULL
      )
),

-- 5. Verify SELECT Policy Specification on relay_logs
select_policy_spec_check AS (
    SELECT 
        '5. SELECT_POLICY_SPECIFICATION' AS check_name,
        CASE 
            WHEN COUNT(*) = 0 THEN 'FAIL'
            WHEN COUNT(*) = 1 
                 AND bool_and(roles = ARRAY['authenticated']::name[]) 
                 AND bool_and(qual LIKE '%is_super_admin%' AND qual LIKE '%is_active_operator%') THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'CRITICAL: No SELECT policy found on public.relay_logs'
            WHEN COUNT(*) = 1 
                 AND bool_and(roles = ARRAY['authenticated']::name[]) 
                 AND bool_and(qual LIKE '%is_super_admin%' AND qual LIKE '%is_active_operator%') THEN 
                'SELECT policy explicitly targets ONLY authenticated and enforces (is_super_admin OR is_active_operator)'
            ELSE 'CRITICAL: SELECT policy mismatch. Found ' || COUNT(*) || ' policy/policies: ' || 
                 string_agg(policyname || ' (roles: ' || array_to_string(roles, ', ') || ', qual: ' || qual || ')', '; ')
        END AS details
    FROM pg_policies
    WHERE schemaname = 'public' 
      AND tablename = 'relay_logs' 
      AND cmd = 'SELECT'
),

-- 6. Check Client INSERT Policies on relay_logs
client_insert_policies_check AS (
    SELECT 
        '6. CLIENT_INSERT_POLICIES' AS check_name,
        CASE 
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'Zero client INSERT policies on public.relay_logs (Direct client table writes blocked)'
            ELSE 'CRITICAL: Found ' || COUNT(*) || ' client INSERT policy/policies: ' || string_agg(policyname || ' (roles: ' || array_to_string(roles, ', ') || ')', ', ')
        END AS details
    FROM pg_policies
    WHERE schemaname = 'public' 
      AND tablename = 'relay_logs' 
      AND cmd = 'INSERT'
      AND NOT (roles = ARRAY['service_role']::name[])
),

-- 7. Check Gateway Ingestion RPC Configuration (SECURITY DEFINER + search_path)
gateway_rpc_check AS (
    SELECT 
        '7. GATEWAY_INGESTION_RPC' AS check_name,
        CASE 
            WHEN p.oid IS NULL THEN 'INFO'
            WHEN p.prosecdef = true 
                 AND EXISTS (
                     SELECT 1 FROM unnest(p.proconfig) cfg 
                     WHERE cfg LIKE 'search_path=%' 
                       AND btrim(substring(cfg from 13), '"'' ') = ''
                 ) THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN p.oid IS NULL THEN 'ingest_lora_relay_packet RPC not yet deployed in public schema (will be created by hardware_lora_relay_security.sql)'
            WHEN p.prosecdef = true 
                 AND EXISTS (
                     SELECT 1 FROM unnest(p.proconfig) cfg 
                     WHERE cfg LIKE 'search_path=%' 
                       AND btrim(substring(cfg from 13), '"'' ') = ''
                 ) THEN 
                'ingest_lora_relay_packet is verified: SECURITY DEFINER with hardened search_path = '''''
            WHEN p.prosecdef != true THEN 'CRITICAL: ingest_lora_relay_packet exists but lacks SECURITY DEFINER attribute'
            ELSE 'CRITICAL: ingest_lora_relay_packet lacks exact hardened search_path = '''' configuration'
        END AS details
    FROM (SELECT 1) dummy
    LEFT JOIN pg_proc p ON p.proname = 'ingest_lora_relay_packet' 
      AND p.pronamespace = 'public'::regnamespace
),

-- 8. Verify public.lora_gateways Registry Table & RLS
gateway_registry_table_check AS (
    SELECT 
        '8. GATEWAY_REGISTRY_TABLE' AS check_name,
        CASE 
            WHEN c.relname IS NULL THEN 'INFO'
            WHEN c.relrowsecurity = true AND anon_public_grants = 0 THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN c.relname IS NULL THEN 'public.lora_gateways table not yet deployed (will be created by hardware_lora_relay_security.sql)'
            WHEN c.relrowsecurity = true AND anon_public_grants = 0 THEN 
                'public.lora_gateways is verified: Table exists, RLS is ACTIVE, and zero privileges granted to anon/PUBLIC'
            WHEN c.relrowsecurity != true THEN 'CRITICAL: Row Level Security is DISABLED on public.lora_gateways'
            ELSE 'CRITICAL: Found ' || anon_public_grants || ' active privilege(s) on public.lora_gateways granted to anon/PUBLIC'
        END AS details
    FROM (SELECT 1) dummy
    LEFT JOIN pg_class c 
      ON c.relname = 'lora_gateways' 
     AND c.relnamespace = 'public'::regnamespace
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS anon_public_grants
        FROM information_schema.role_table_grants
        WHERE table_schema = 'public' 
          AND table_name = 'lora_gateways' 
          AND grantee IN ('anon', 'PUBLIC')
    ) g ON true
),

-- 9. Verify Super Admin Gateway Management RPCs
gateway_admin_rpcs_check AS (
    SELECT 
        '9. GATEWAY_ADMIN_RPCS' AS check_name,
        CASE 
            WHEN COUNT(p.proname) = 0 THEN 'INFO'
            WHEN COUNT(p.proname) = 3 
                 AND bool_and(p.prosecdef = true)
                 AND bool_and(has_hardened_path)
                 AND bool_and(NOT has_anon_grant) THEN 'PASS'
            ELSE 'FAIL'
        END AS status,
        CASE 
            WHEN COUNT(p.proname) = 0 THEN 'Gateway admin RPCs not yet deployed (will be created by hardware_lora_relay_security.sql)'
            WHEN COUNT(p.proname) = 3 
                 AND bool_and(p.prosecdef = true)
                 AND bool_and(has_hardened_path)
                 AND bool_and(NOT has_anon_grant) THEN 
                'All 3 Super Admin gateway RPCs (register, set_status, rotate_token) verified: SECURITY DEFINER, search_path = '''', anon/PUBLIC revoked'
            ELSE 'CRITICAL: Gateway admin RPC configuration mismatch. Found ' || COUNT(p.proname) || ' of 3 RPCs'
        END AS details
    FROM (
        VALUES 
            ('admin_register_lora_gateway'),
            ('admin_set_lora_gateway_status'),
            ('admin_rotate_lora_gateway_token')
    ) AS req(proname)
    LEFT JOIN (
        SELECT 
            p.proname,
            p.prosecdef,
            EXISTS (
                SELECT 1 FROM unnest(p.proconfig) cfg 
                WHERE cfg LIKE 'search_path=%' 
                  AND btrim(substring(cfg from 13), '"'' ') = ''
            ) AS has_hardened_path,
            has_function_privilege('anon', p.oid, 'EXECUTE') AS has_anon_grant
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
    ) p ON p.proname = req.proname
),

-- 10. Data Row Count Baseline Check
data_baseline_check AS (
    SELECT 
        '10. DATA_ROW_COUNT_BASELINE' AS check_name,
        'INFO' AS status,
        'relay_logs: ' || (SELECT count(*) FROM public.relay_logs) || ' record(s); ' ||
        CASE 
            WHEN to_regclass('public.lora_gateways') IS NOT NULL THEN
                'lora_gateways: ' || COALESCE(
                    (xpath('/table/row/count/text()', query_to_xml('SELECT count(*) FROM public.lora_gateways', false, false, '')))[1]::text,
                    '0'
                ) || ' registered gateway(s).'
            ELSE 'lora_gateways: table not yet created (0 gateways registered).'
        END AS details
)

-- Combined Read-Only Verification Report
SELECT 
    check_name,
    status,
    details
FROM (
    SELECT * FROM privilege_anon_public
    UNION ALL
    SELECT * FROM privilege_authenticated
    UNION ALL
    SELECT * FROM rls_status_check
    UNION ALL
    SELECT * FROM anonymous_policies_check
    UNION ALL
    SELECT * FROM select_policy_spec_check
    UNION ALL
    SELECT * FROM client_insert_policies_check
    UNION ALL
    SELECT * FROM gateway_rpc_check
    UNION ALL
    SELECT * FROM gateway_registry_table_check
    UNION ALL
    SELECT * FROM gateway_admin_rpcs_check
    UNION ALL
    SELECT * FROM data_baseline_check
) report
ORDER BY check_name;
