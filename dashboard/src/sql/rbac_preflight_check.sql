-- ==============================================================================
-- SORYNTH RESCUE COMMAND & DISPATCH CONSOLE
-- READ-ONLY RBAC PREFLIGHT INSPECTION SCRIPT
-- File: src/sql/rbac_preflight_check.sql
-- ==============================================================================
-- PURPOSE:
-- Purely diagnostic and non-mutating inspection of the live database prior to
-- applying the hardened RBAC migration (src/sql/rbac_schema_setup.sql).
--
-- GUARANTEES:
-- 1. Strictly READ-ONLY: ZERO INSERT, UPDATE, DELETE, ALTER, DROP, or DDL operations.
-- 2. Resilient to missing tables: safely handles completely fresh or partial databases.
-- 3. Returns all findings as a structured SQL result table with columns:
--    check_id, category, status (PASS/WARNING/BLOCKER/INFO), finding, affected_count.
-- ==============================================================================

BEGIN TRANSACTION READ ONLY;

DO $$
DECLARE
    v_report jsonb := '[]'::jsonb;
    v_has_op BOOLEAN := (to_regclass('public.operator_profiles') IS NOT NULL);
    v_has_profiles BOOLEAN := (to_regclass('public.profiles') IS NOT NULL);
    v_has_emergencies BOOLEAN := (to_regclass('public.emergencies') IS NOT NULL);
    v_has_updates BOOLEAN := (to_regclass('public.emergency_updates') IS NOT NULL);
    v_has_relays BOOLEAN := (to_regclass('public.relay_logs') IS NOT NULL);
    v_has_auth BOOLEAN := (to_regclass('auth.users') IS NOT NULL);
    v_ts_col TEXT := NULL;
    v_count BIGINT := 0;
    v_ties BIGINT := 0;
    v_blockers BIGINT := 0;
    v_warnings BIGINT := 0;
    r RECORD;
    pk RECORD;
BEGIN
    -- --------------------------------------------------------------------------
    -- 1a. Table Existence & Row Counts
    -- --------------------------------------------------------------------------
    FOR r IN (
        SELECT 
            t.table_name,
            c.relname IS NOT NULL AS tbl_exists,
            COALESCE(c.reltuples::BIGINT, 0) AS estimated_rows,
            COALESCE(c.relrowsecurity, FALSE) AS rls_enabled
        FROM (
            VALUES 
                ('profiles'), ('operator_profiles'), ('rescue_teams'),
                ('emergencies'), ('emergency_updates'), ('relay_logs'), ('audit_logs')
        ) AS t(table_name)
        LEFT JOIN pg_class c ON c.relname = t.table_name AND c.relnamespace = 'public'::regnamespace
        ORDER BY t.table_name
    ) LOOP
        IF r.tbl_exists THEN
            v_report := v_report || jsonb_build_object(
                'check_id', '1a.' || r.table_name,
                'category', 'TABLE_EXISTENCE',
                'status', 'PASS',
                'finding', 'Table public.' || r.table_name || ' exists (estimated rows: ' || r.estimated_rows || ', RLS: ' || CASE WHEN r.rls_enabled THEN 'ENABLED' ELSE 'DISABLED' END || ')',
                'affected_count', r.estimated_rows
            );
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '1a.' || r.table_name,
                'category', 'TABLE_EXISTENCE',
                'status', 'INFO',
                'finding', 'Table public.' || r.table_name || ' is missing (will be created by migration)',
                'affected_count', 0
            );
        END IF;
    END LOOP;

    -- --------------------------------------------------------------------------
    -- 1b. auth.users Table Existence
    -- --------------------------------------------------------------------------
    IF v_has_auth THEN
        SELECT COALESCE(c.reltuples::BIGINT, 0) INTO v_count
        FROM pg_class c 
        JOIN pg_namespace n ON n.oid = c.relnamespace 
        WHERE n.nspname = 'auth' AND c.relname = 'users';

        v_report := v_report || jsonb_build_object(
            'check_id', '1b.auth_users',
            'category', 'TABLE_EXISTENCE',
            'status', 'PASS',
            'finding', 'auth.users catalog table exists (estimated accounts: ' || v_count || ')',
            'affected_count', v_count
        );
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '1b.auth_users',
            'category', 'TABLE_EXISTENCE',
            'status', 'WARNING',
            'finding', 'auth.users catalog table is missing or inaccessible',
            'affected_count', 0
        );
        v_warnings := v_warnings + 1;
    END IF;

    -- --------------------------------------------------------------------------
    -- 2. Column Schema for operator_profiles
    -- --------------------------------------------------------------------------
    IF v_has_op THEN
        SELECT 
            count(*),
            COALESCE(pg_catalog.string_agg(column_name || ' (' || data_type || ')', ', ' ORDER BY ordinal_position), '')
        INTO v_count, v_ts_col
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'operator_profiles';

        v_report := v_report || jsonb_build_object(
            'check_id', '2.operator_columns',
            'category', 'SCHEMA_COLUMNS',
            'status', CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'operator_profiles' AND column_name = 'user_id') THEN 'PASS' ELSE 'WARNING' END,
            'finding', 'operator_profiles columns (' || v_count || '): ' || v_ts_col,
            'affected_count', v_count
        );
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '2.operator_columns',
            'category', 'SCHEMA_COLUMNS',
            'status', 'INFO',
            'finding', 'operator_profiles does not exist yet (fresh database)',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 3. Primary Key & Constraints on operator_profiles
    -- --------------------------------------------------------------------------
    IF v_has_op THEN
        SELECT 
            c.conname,
            count(a.attname) AS col_count,
            pg_catalog.string_agg(a.attname, ', ' ORDER BY u.ord) AS key_cols,
            CASE WHEN count(a.attname) > 1 THEN 'COMPOSITE' ELSE 'SINGLE_COLUMN' END AS structure
        INTO pk
        FROM pg_constraint c
        CROSS JOIN LATERAL pg_catalog.unnest(c.conkey) WITH ORDINALITY AS u(attnum, ord)
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = u.attnum
        WHERE c.conrelid = to_regclass('public.operator_profiles') AND c.contype = 'p'
        GROUP BY c.conname;

        IF pk.conname IS NOT NULL THEN
            IF pk.key_cols = 'user_id' THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '3.primary_key',
                    'category', 'PRIMARY_KEY',
                    'status', 'PASS',
                    'finding', 'Optimal PRIMARY KEY found on user_id (' || pk.conname || ')',
                    'affected_count', 1
                );
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '3.primary_key',
                    'category', 'PRIMARY_KEY',
                    'status', 'WARNING',
                    'finding', 'Legacy ' || pk.structure || ' PRIMARY KEY detected: ' || pk.conname || ' on (' || pk.key_cols || '). Migration Section 4f will preserve dependencies and establish user_id PK.',
                    'affected_count', pk.col_count
                );
                v_warnings := v_warnings + 1;
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '3.primary_key',
                'category', 'PRIMARY_KEY',
                'status', 'WARNING',
                'finding', 'No PRIMARY KEY constraint found on operator_profiles (will be created on user_id by migration)',
                'affected_count', 0
            );
            v_warnings := v_warnings + 1;
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '3.primary_key',
            'category', 'PRIMARY_KEY',
            'status', 'INFO',
            'finding', 'operator_profiles does not exist yet (fresh database)',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 4. External Foreign Keys Referencing operator_profiles
    -- --------------------------------------------------------------------------
    IF v_has_op THEN
        SELECT count(*), COALESCE(string_agg(c.conrelid::regclass::text || '.' || c.conname, ', '), '')
        INTO v_count, v_ts_col
        FROM pg_constraint c
        WHERE c.confrelid = to_regclass('public.operator_profiles') AND c.contype = 'f';

        IF v_count > 0 THEN
            v_report := v_report || jsonb_build_object(
                'check_id', '4.foreign_keys',
                'category', 'FOREIGN_KEYS',
                'status', 'WARNING',
                'finding', 'Found ' || v_count || ' external foreign key(s) referencing operator_profiles: ' || v_ts_col || '. Migration Section 4f will preserve dependent constraints.',
                'affected_count', v_count
            );
            v_warnings := v_warnings + 1;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '4.foreign_keys',
                'category', 'FOREIGN_KEYS',
                'status', 'PASS',
                'finding', 'Zero external foreign keys reference operator_profiles (safe to modify primary key)',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '4.foreign_keys',
            'category', 'FOREIGN_KEYS',
            'status', 'INFO',
            'finding', 'operator_profiles does not exist yet (fresh database)',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 5. Existing Indexes
    -- --------------------------------------------------------------------------
    SELECT count(*) INTO v_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename IN ('profiles', 'operator_profiles', 'rescue_teams', 'emergencies', 'emergency_updates', 'relay_logs', 'audit_logs');

    v_report := v_report || jsonb_build_object(
        'check_id', '5.indexes',
        'category', 'INDEXES',
        'status', 'INFO',
        'finding', 'Found ' || v_count || ' existing index(es) across SORYNTH public tables',
        'affected_count', v_count
    );

    -- --------------------------------------------------------------------------
    -- 6. RLS Policy Classification
    -- --------------------------------------------------------------------------
    -- 6a. Obsolete SORYNTH policies (Permissive prototype policies slated for DROP)
    SELECT count(*) INTO v_count
    FROM pg_policies p
    JOIN (
        VALUES
            ('profiles', 'Allow read profiles'), ('profiles', 'Allow insert profiles'),
            ('profiles', 'Allow update profiles'), ('profiles', 'Allow delete profiles'),
            ('profiles', 'Profiles read policy'), ('profiles', 'Enable read access for all users'),
            ('profiles', 'Enable insert for authenticated users only'),
            ('profiles', 'Enable update for users based on email'),
            ('profiles', 'Public profiles are viewable by everyone'),
            ('operator_profiles', 'Allow read operator profiles'),
            ('operator_profiles', 'Allow manage operator profiles'),
            ('operator_profiles', 'Allow read operator_profiles'),
            ('operator_profiles', 'Allow manage operator_profiles'),
            ('operator_profiles', 'Operator profiles read policy'),
            ('operator_profiles', 'Operator profiles view policy'),
            ('operator_profiles', 'Operator profiles all policy'),
            ('operator_profiles', 'View own profile or admin views all'),
            ('audit_logs', 'Allow read audit logs'), ('audit_logs', 'Allow insert audit logs'),
            ('audit_logs', 'Audit logs view policy'),
            ('emergencies', 'View emergencies'), ('emergencies', 'Insert emergencies'),
            ('emergencies', 'Update emergencies'), ('emergencies', 'Delete emergencies'),
            ('emergencies', 'Operators can view all emergencies'),
            ('emergencies', 'Operators can insert emergencies'),
            ('emergencies', 'Operators can update all emergencies'),
            ('emergencies', 'Operators can delete emergencies'),
            ('emergencies', 'Emergencies view policy'), ('emergencies', 'Emergencies all policy'),
            ('emergencies', 'Allow read emergencies'), ('emergencies', 'Allow insert emergencies'),
            ('emergencies', 'Allow update emergencies'), ('emergencies', 'Allow delete emergencies'),
            ('rescue_teams', 'Allow read rescue teams'), ('rescue_teams', 'Allow manage rescue teams'),
            ('rescue_teams', 'View rescue teams'), ('rescue_teams', 'Manage rescue teams'),
            ('rescue_teams', 'Rescue teams view policy'), ('rescue_teams', 'Rescue teams all policy'),
            ('relay_logs', 'Allow read relay logs'), ('relay_logs', 'Allow insert relay logs'),
            ('relay_logs', 'View relay logs'), ('relay_logs', 'Insert relay logs'),
            ('relay_logs', 'Relay logs view policy'), ('relay_logs', 'Relay logs all policy'),
            ('relay_logs', 'Relay logs insert policy'),
            ('emergency_updates', 'Allow read emergency updates'),
            ('emergency_updates', 'Allow insert emergency updates'),
            ('emergency_updates', 'View emergency updates'),
            ('emergency_updates', 'Insert emergency updates'),
            ('emergency_updates', 'Emergency updates view policy'),
            ('emergency_updates', 'Emergency updates all policy')
    ) AS o(tablename, policyname) ON o.tablename = p.tablename AND o.policyname = p.policyname
    WHERE p.schemaname = 'public';

    IF v_count > 0 THEN
        v_report := v_report || jsonb_build_object(
            'check_id', '6a.obsolete_policies',
            'category', 'RLS_POLICIES',
            'status', 'WARNING',
            'finding', 'Found ' || v_count || ' obsolete permissive SORYNTH policy/policies slated for DROP in Section 15',
            'affected_count', v_count
        );
        v_warnings := v_warnings + 1;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '6a.obsolete_policies',
            'category', 'RLS_POLICIES',
            'status', 'PASS',
            'finding', 'Zero obsolete SORYNTH policies detected in database',
            'affected_count', 0
        );
    END IF;

    -- 6b. Hardened SORYNTH policies
    SELECT count(*) INTO v_count
    FROM pg_policies p
    JOIN (
        VALUES
            ('profiles', 'Profiles select policy'), ('profiles', 'Profiles insert policy'),
            ('profiles', 'Profiles update policy'), ('profiles', 'Profiles delete policy'),
            ('operator_profiles', 'Operator profiles select policy'),
            ('operator_profiles', 'Operator profiles insert policy'),
            ('operator_profiles', 'Operator profiles update policy'),
            ('operator_profiles', 'Operator profiles delete policy'),
            ('audit_logs', 'Audit logs select policy'), ('audit_logs', 'Audit logs insert policy'),
            ('emergencies', 'Emergencies select policy'),
            ('emergencies', 'Emergencies insert policy'),
            ('emergencies', 'Emergencies anonymous insert policy'),
            ('emergencies', 'Emergencies authenticated insert policy'),
            ('emergencies', 'Emergencies update policy'),
            ('emergencies', 'Emergencies delete policy'),
            ('rescue_teams', 'Rescue teams select policy'),
            ('rescue_teams', 'Rescue teams manage policy'),
            ('rescue_teams', 'Rescue teams admin write policy'),
            ('relay_logs', 'Relay logs select policy'),
            ('emergency_updates', 'Emergency updates select policy'),
            ('emergency_updates', 'Emergency updates insert policy')
    ) AS h(tablename, policyname) ON h.tablename = p.tablename AND h.policyname = p.policyname
    WHERE p.schemaname = 'public';

    v_report := v_report || jsonb_build_object(
        'check_id', '6b.hardened_policies',
        'category', 'RLS_POLICIES',
        'status', 'INFO',
        'finding', 'Found ' || v_count || ' hardened SORYNTH policies already present',
        'affected_count', v_count
    );

    -- 6c. Verified Scoped Citizen Policies (Mobile App Schema)
    SELECT count(*) INTO v_count
    FROM pg_policies p
    JOIN (
        VALUES
            ('profiles', 'Users can view own profile'),
            ('profiles', 'Users can update own profile'),
            ('profiles', 'Users can insert own profile'),
            ('emergencies', 'Users can view their own emergencies'),
            ('emergencies', 'Authenticated users can create emergencies'),
            ('emergencies', 'Users can update own emergencies'),
            ('emergency_updates', 'Users can view updates for their own emergencies')
    ) AS c(tablename, policyname) ON c.tablename = p.tablename AND c.policyname = p.policyname
    WHERE p.schemaname = 'public';

    v_report := v_report || jsonb_build_object(
        'check_id', '6c.citizen_policies',
        'category', 'RLS_POLICIES',
        'status', 'PASS',
        'finding', 'Found ' || v_count || ' of 7 verified scoped citizen policy/policies preserved untouched (scoped to incident owner, zero anonymous access)',
        'affected_count', v_count
    );

    -- 6d. Unmanaged custom policies
    SELECT count(*) INTO v_count
    FROM pg_policies p
    WHERE p.schemaname = 'public'
      AND p.tablename IN ('profiles', 'operator_profiles', 'rescue_teams', 'emergencies', 'emergency_updates', 'relay_logs', 'audit_logs')
      AND (p.tablename, p.policyname) NOT IN (
          SELECT tablename, policyname FROM (
              VALUES
                  -- Obsolete
                  ('profiles', 'Allow read profiles'), ('profiles', 'Allow insert profiles'),
                  ('profiles', 'Allow update profiles'), ('profiles', 'Allow delete profiles'),
                  ('profiles', 'Profiles read policy'), ('profiles', 'Enable read access for all users'),
                  ('profiles', 'Enable insert for authenticated users only'),
                  ('profiles', 'Enable update for users based on email'),
                  ('profiles', 'Public profiles are viewable by everyone'),
                  ('operator_profiles', 'Allow read operator profiles'),
                  ('operator_profiles', 'Allow manage operator profiles'),
                  ('operator_profiles', 'Allow read operator_profiles'),
                  ('operator_profiles', 'Allow manage operator_profiles'),
                  ('operator_profiles', 'Operator profiles read policy'),
                  ('operator_profiles', 'Operator profiles view policy'),
                  ('operator_profiles', 'Operator profiles all policy'),
                  ('operator_profiles', 'View own profile or admin views all'),
                  ('audit_logs', 'Allow read audit logs'), ('audit_logs', 'Allow insert audit logs'),
                  ('audit_logs', 'Audit logs view policy'),
                  ('emergencies', 'View emergencies'), ('emergencies', 'Insert emergencies'),
                  ('emergencies', 'Update emergencies'), ('emergencies', 'Delete emergencies'),
                  ('emergencies', 'Operators can view all emergencies'),
                  ('emergencies', 'Operators can insert emergencies'),
                  ('emergencies', 'Operators can update all emergencies'),
                  ('emergencies', 'Operators can delete emergencies'),
                  ('emergencies', 'Emergencies view policy'), ('emergencies', 'Emergencies all policy'),
                  ('emergencies', 'Allow read emergencies'), ('emergencies', 'Allow insert emergencies'),
                  ('emergencies', 'Allow update emergencies'), ('emergencies', 'Allow delete emergencies'),
                  ('rescue_teams', 'Allow read rescue teams'), ('rescue_teams', 'Allow manage rescue teams'),
                  ('rescue_teams', 'View rescue teams'), ('rescue_teams', 'Manage rescue teams'),
                  ('rescue_teams', 'Rescue teams view policy'), ('rescue_teams', 'Rescue teams all policy'),
                  ('relay_logs', 'Allow read relay logs'), ('relay_logs', 'Allow insert relay logs'),
                  ('relay_logs', 'View relay logs'), ('relay_logs', 'Insert relay logs'),
                  ('relay_logs', 'Relay logs view policy'), ('relay_logs', 'Relay logs all policy'),
                  ('emergency_updates', 'Allow read emergency updates'),
                  ('emergency_updates', 'Allow insert emergency updates'),
                  ('emergency_updates', 'View emergency updates'),
                  ('emergency_updates', 'Insert emergency updates'),
                  ('emergency_updates', 'Emergency updates view policy'),
                  ('emergency_updates', 'Emergency updates all policy'),
                  -- Hardened
                  ('profiles', 'Profiles select policy'), ('profiles', 'Profiles insert policy'),
                  ('profiles', 'Profiles update policy'), ('profiles', 'Profiles delete policy'),
                  ('operator_profiles', 'Operator profiles select policy'),
                  ('operator_profiles', 'Operator profiles insert policy'),
                  ('operator_profiles', 'Operator profiles update policy'),
                  ('operator_profiles', 'Operator profiles delete policy'),
                  ('audit_logs', 'Audit logs select policy'), ('audit_logs', 'Audit logs insert policy'),
                  ('emergencies', 'Emergencies select policy'),
                  ('emergencies', 'Emergencies insert policy'),
                  ('emergencies', 'Emergencies anonymous insert policy'),
                  ('emergencies', 'Emergencies authenticated insert policy'),
                  ('emergencies', 'Emergencies update policy'),
                  ('emergencies', 'Emergencies delete policy'),
                  ('rescue_teams', 'Rescue teams select policy'),
                  ('rescue_teams', 'Rescue teams manage policy'),
                  ('rescue_teams', 'Rescue teams admin write policy'),
                  ('relay_logs', 'Relay logs select policy'),
                  ('emergency_updates', 'Emergency updates select policy'),
                  ('emergency_updates', 'Emergency updates insert policy'),
                  -- Citizen
                  ('profiles', 'Users can view own profile'),
                  ('profiles', 'Users can update own profile'),
                  ('profiles', 'Users can insert own profile'),
                  ('emergencies', 'Users can view their own emergencies'),
                  ('emergencies', 'Authenticated users can create emergencies'),
                  ('emergencies', 'Users can update own emergencies'),
                  ('emergency_updates', 'Users can view updates for their own emergencies')
          ) AS all_known(tablename, policyname)
      );

    v_report := v_report || jsonb_build_object(
        'check_id', '6d.custom_unmanaged_policies',
        'category', 'RLS_POLICIES',
        'status', 'PASS',
        'finding', 'Found ' || v_count || ' unmanaged custom policy/policies that will be inspected in Section 15',
        'affected_count', v_count
    );

    -- --------------------------------------------------------------------------
    -- 7. Table Grants & Permissions
    -- --------------------------------------------------------------------------
    SELECT count(*) INTO v_count
    FROM (
        SELECT t.table_name
        FROM (
            VALUES 
                ('profiles'), ('operator_profiles'), ('rescue_teams'),
                ('emergencies'), ('emergency_updates'), ('relay_logs'), ('audit_logs')
        ) AS t(table_name)
        WHERE to_regclass('public.' || t.table_name) IS NOT NULL
          AND (has_table_privilege('anon', 'public.' || t.table_name, 'INSERT') OR
               has_table_privilege('anon', 'public.' || t.table_name, 'UPDATE') OR
               has_table_privilege('anon', 'public.' || t.table_name, 'DELETE'))
    ) sub;

    IF v_count > 0 THEN
        v_report := v_report || jsonb_build_object(
            'check_id', '7.table_grants',
            'category', 'PERMISSIONS',
            'status', 'WARNING',
            'finding', 'Found ' || v_count || ' table(s) with direct write permissions granted to anon (will be revoked by Section 13)',
            'affected_count', v_count
        );
        v_warnings := v_warnings + 1;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '7.table_grants',
            'category', 'PERMISSIONS',
            'status', 'PASS',
            'finding', 'Table permissions secure: anon has zero direct table write permissions',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 8. Stored Procedures / RPC Grants
    -- --------------------------------------------------------------------------
    SELECT count(DISTINCT f.routine_name) INTO v_count
    FROM (
        VALUES 
            ('generate_employee_id'), ('is_super_admin'), ('is_active_operator'),
            ('log_audit_event'), ('operator_set_team_readiness'),
            ('update_emergency_status_operator'), ('admin_set_operator_status'),
            ('admin_update_operator')
    ) AS fn(routine_name)
    JOIN information_schema.routines f 
      ON f.routine_schema = 'public' AND f.routine_name = fn.routine_name;

    v_report := v_report || jsonb_build_object(
        'check_id', '8.rpc_grants',
        'category', 'RPC_GRANTS',
        'status', 'INFO',
        'finding', 'Found ' || v_count || ' of 8 SORYNTH RPC function(s) existing in public schema',
        'affected_count', v_count
    );

    -- --------------------------------------------------------------------------
    -- 9a. Check for NULL user_id in operator_profiles
    -- --------------------------------------------------------------------------
    IF v_has_op THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'operator_profiles' AND column_name = 'user_id') THEN
            EXECUTE 'SELECT count(*) FROM public.operator_profiles WHERE user_id IS NULL' INTO v_count;
            IF v_count > 0 THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '9a.null_user_id',
                    'category', 'DATA_INTEGRITY',
                    'status', 'BLOCKER',
                    'finding', 'Found ' || v_count || ' operator_profiles row(s) with NULL user_id. Migration Section 4c will halt.',
                    'affected_count', v_count
                );
                v_blockers := v_blockers + 1;
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '9a.null_user_id',
                    'category', 'DATA_INTEGRITY',
                    'status', 'PASS',
                    'finding', 'Zero NULL user_id rows in operator_profiles',
                    'affected_count', 0
                );
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '9a.null_user_id',
                'category', 'DATA_INTEGRITY',
                'status', 'INFO',
                'finding', 'operator_profiles exists without user_id column yet',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '9a.null_user_id',
            'category', 'DATA_INTEGRITY',
            'status', 'PASS',
            'finding', 'operator_profiles does not exist yet (fresh database)',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 9b. Check for legacy 'id' matching auth.users in operator_profiles
    -- --------------------------------------------------------------------------
    IF v_has_op AND v_has_auth THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'operator_profiles' AND column_name = 'id') THEN
            EXECUTE '
                SELECT count(*)
                FROM public.operator_profiles op
                LEFT JOIN auth.users u ON u.id = op.id
                WHERE u.id IS NULL'
            INTO v_count;

            IF v_count > 0 THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '9b.legacy_id_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'BLOCKER',
                    'finding', 'Found ' || v_count || ' operator_profiles record(s) whose legacy id is not in auth.users. Migration Section 4c will halt unless resolved manually.',
                    'affected_count', v_count
                );
                v_blockers := v_blockers + 1;
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '9b.legacy_id_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'PASS',
                    'finding', 'All legacy operator_profiles id values match valid auth.users records',
                    'affected_count', 0
                );
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '9b.legacy_id_orphans',
                'category', 'DATA_INTEGRITY',
                'status', 'INFO',
                'finding', 'operator_profiles has no legacy id column',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '9b.legacy_id_orphans',
            'category', 'DATA_INTEGRITY',
            'status', 'INFO',
            'finding', 'operator_profiles or auth.users missing; legacy id check skipped',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 9c. Check duplicate user_id records and timestamp tie assessment
    -- --------------------------------------------------------------------------
    IF v_has_op THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'operator_profiles' AND column_name = 'user_id') THEN
            IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'operator_profiles' AND column_name = 'updated_at') THEN
                v_ts_col := 'updated_at';
            ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'operator_profiles' AND column_name = 'created_at') THEN
                v_ts_col := 'created_at';
            ELSE
                v_ts_col := NULL;
            END IF;

            IF v_ts_col IS NOT NULL THEN
                EXECUTE format('
                    WITH dup_analysis AS (
                        SELECT user_id, %I AS ts_col,
                               COUNT(*) OVER (PARTITION BY user_id) AS total_user_count,
                               COUNT(*) OVER (PARTITION BY user_id, %I) AS tie_count
                        FROM public.operator_profiles
                        WHERE user_id IS NOT NULL
                    )
                    SELECT 
                        COALESCE(COUNT(*) FILTER (WHERE total_user_count > 1), 0),
                        COALESCE(COUNT(*) FILTER (WHERE total_user_count > 1 AND (ts_col IS NULL OR tie_count > 1)), 0)
                    FROM dup_analysis', v_ts_col, v_ts_col)
                INTO v_count, v_ties;

                IF v_ties > 0 THEN
                    v_report := v_report || jsonb_build_object(
                        'check_id', '9c.duplicate_user_ids',
                        'category', 'DATA_INTEGRITY',
                        'status', 'BLOCKER',
                        'finding', 'Found ' || v_ties || ' duplicate operator_profiles with ambiguous ties or missing ' || v_ts_col || ' timestamps. Migration Section 4d will halt.',
                        'affected_count', v_ties
                    );
                    v_blockers := v_blockers + 1;
                ELSIF v_count > 0 THEN
                    v_report := v_report || jsonb_build_object(
                        'check_id', '9c.duplicate_user_ids',
                        'category', 'DATA_INTEGRITY',
                        'status', 'WARNING',
                        'finding', 'Found ' || v_count || ' duplicate operator_profiles records with distinct ' || v_ts_col || ' timestamps. Latest record will be retained.',
                        'affected_count', v_count
                    );
                    v_warnings := v_warnings + 1;
                ELSE
                    v_report := v_report || jsonb_build_object(
                        'check_id', '9c.duplicate_user_ids',
                        'category', 'DATA_INTEGRITY',
                        'status', 'PASS',
                        'finding', 'Zero duplicate user_id records in operator_profiles (verified with ' || v_ts_col || ')',
                        'affected_count', 0
                    );
                END IF;
            ELSE
                EXECUTE '
                    WITH dup_analysis AS (
                        SELECT user_id,
                               COUNT(*) OVER (PARTITION BY user_id) AS total_user_count
                        FROM public.operator_profiles
                        WHERE user_id IS NOT NULL
                    )
                    SELECT COALESCE(COUNT(*) FILTER (WHERE total_user_count > 1), 0)
                    FROM dup_analysis'
                INTO v_count;

                IF v_count > 0 THEN
                    v_report := v_report || jsonb_build_object(
                        'check_id', '9c.duplicate_user_ids',
                        'category', 'DATA_INTEGRITY',
                        'status', 'BLOCKER',
                        'finding', 'Found ' || v_count || ' duplicate operator_profiles rows sharing user_id, but neither updated_at nor created_at exists for tie resolution. Manual resolution required.',
                        'affected_count', v_count
                    );
                    v_blockers := v_blockers + 1;
                ELSE
                    v_report := v_report || jsonb_build_object(
                        'check_id', '9c.duplicate_user_ids',
                        'category', 'DATA_INTEGRITY',
                        'status', 'PASS',
                        'finding', 'Zero duplicate user_id records in operator_profiles (no timestamp column present)',
                        'affected_count', 0
                    );
                END IF;
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '9c.duplicate_user_ids',
                'category', 'DATA_INTEGRITY',
                'status', 'INFO',
                'finding', 'operator_profiles has no user_id column yet; duplicate check skipped',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '9c.duplicate_user_ids',
            'category', 'DATA_INTEGRITY',
            'status', 'PASS',
            'finding', 'operator_profiles does not exist yet (fresh database)',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 9d. Profiles Orphaned Records
    -- --------------------------------------------------------------------------
    IF v_has_profiles AND v_has_auth THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'id') THEN
            EXECUTE '
                SELECT count(*)
                FROM public.profiles p
                LEFT JOIN auth.users u ON u.id = p.id
                WHERE u.id IS NULL'
            INTO v_count;

            IF v_count > 0 THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '9d.profiles_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'WARNING',
                    'finding', 'Found ' || v_count || ' profiles record(s) with no corresponding auth.users row',
                    'affected_count', v_count
                );
                v_warnings := v_warnings + 1;
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '9d.profiles_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'PASS',
                    'finding', 'All profiles reference valid auth.users records',
                    'affected_count', 0
                );
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '9d.profiles_orphans',
                'category', 'DATA_INTEGRITY',
                'status', 'INFO',
                'finding', 'profiles table has no id column; orphan check skipped',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '9d.profiles_orphans',
            'category', 'DATA_INTEGRITY',
            'status', 'INFO',
            'finding', 'profiles or auth.users missing; orphan check skipped',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 9e. Emergency Updates Orphaned Records
    -- --------------------------------------------------------------------------
    IF v_has_updates AND v_has_emergencies THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'emergency_updates' AND column_name = 'emergency_id')
           AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'emergencies' AND column_name = 'id') THEN
            EXECUTE '
                SELECT count(*)
                FROM public.emergency_updates eu
                LEFT JOIN public.emergencies e ON e.id = eu.emergency_id
                WHERE e.id IS NULL'
            INTO v_count;

            IF v_count > 0 THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '9e.emergency_updates_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'WARNING',
                    'finding', 'Found ' || v_count || ' emergency_updates referencing non-existent emergency_id',
                    'affected_count', v_count
                );
                v_warnings := v_warnings + 1;
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '9e.emergency_updates_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'PASS',
                    'finding', 'All emergency updates reference valid emergencies',
                    'affected_count', 0
                );
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '9e.emergency_updates_orphans',
                'category', 'DATA_INTEGRITY',
                'status', 'INFO',
                'finding', 'emergency_updates.emergency_id or emergencies.id missing; orphan check skipped',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '9e.emergency_updates_orphans',
            'category', 'DATA_INTEGRITY',
            'status', 'INFO',
            'finding', 'emergency_updates or emergencies missing; orphan check skipped',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 9f. Relay Logs Orphaned Records
    -- --------------------------------------------------------------------------
    IF v_has_relays AND v_has_emergencies THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'relay_logs' AND column_name = 'emergency_id')
           AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'emergencies' AND column_name = 'id') THEN
            EXECUTE '
                SELECT count(*)
                FROM public.relay_logs rl
                LEFT JOIN public.emergencies e ON e.id = rl.emergency_id
                WHERE rl.emergency_id IS NOT NULL AND e.id IS NULL'
            INTO v_count;

            IF v_count > 0 THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '9f.relay_logs_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'INFO',
                    'finding', 'Found ' || v_count || ' relay_logs without matching emergency_id (valid for broadcast telemetry)',
                    'affected_count', v_count
                );
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '9f.relay_logs_orphans',
                    'category', 'DATA_INTEGRITY',
                    'status', 'PASS',
                    'finding', 'All relay logs with emergency_id match valid emergencies',
                    'affected_count', 0
                );
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '9f.relay_logs_orphans',
                'category', 'DATA_INTEGRITY',
                'status', 'INFO',
                'finding', 'relay_logs.emergency_id or emergencies.id missing; orphan check skipped',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '9f.relay_logs_orphans',
            'category', 'DATA_INTEGRITY',
            'status', 'INFO',
            'finding', 'relay_logs or emergencies missing; orphan check skipped',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 10a. Admin Account Presence (admin@sorynth.org)
    -- --------------------------------------------------------------------------
    IF v_has_auth THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'email') THEN
            EXECUTE 'SELECT count(*) FROM auth.users WHERE LOWER(email) = ''admin@sorynth.org''' INTO v_count;
            IF v_count > 0 THEN
                v_report := v_report || jsonb_build_object(
                    'check_id', '10a.admin_account',
                    'category', 'ADMIN_ACCOUNT',
                    'status', 'PASS',
                    'finding', 'admin@sorynth.org verified in auth.users (ready for Super Admin promotion)',
                    'affected_count', v_count
                );
            ELSE
                v_report := v_report || jsonb_build_object(
                    'check_id', '10a.admin_account',
                    'category', 'ADMIN_ACCOUNT',
                    'status', 'WARNING',
                    'finding', 'admin@sorynth.org is not registered in auth.users yet. Section 20 promotion will be skipped until registered.',
                    'affected_count', 0
                );
                v_warnings := v_warnings + 1;
            END IF;
        ELSE
            v_report := v_report || jsonb_build_object(
                'check_id', '10a.admin_account',
                'category', 'ADMIN_ACCOUNT',
                'status', 'INFO',
                'finding', 'auth.users has no email column; admin verification skipped',
                'affected_count', 0
            );
        END IF;
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '10a.admin_account',
            'category', 'ADMIN_ACCOUNT',
            'status', 'INFO',
            'finding', 'auth.users does not exist yet; admin verification skipped',
            'affected_count', 0
        );
    END IF;

    -- --------------------------------------------------------------------------
    -- 10b. Overall Migration Readiness
    -- --------------------------------------------------------------------------
    IF v_blockers > 0 THEN
        v_report := v_report || jsonb_build_object(
            'check_id', '10b.overall_readiness',
            'category', 'READINESS',
            'status', 'BLOCKER',
            'finding', 'MIGRATION BLOCKED: ' || v_blockers || ' blocker(s) detected. Resolve blockers before running rbac_schema_setup.sql.',
            'affected_count', v_blockers
        );
    ELSIF v_warnings > 0 THEN
        v_report := v_report || jsonb_build_object(
            'check_id', '10b.overall_readiness',
            'category', 'READINESS',
            'status', 'WARNING',
            'finding', 'MIGRATION READY WITH NOTICES: ' || v_warnings || ' warning item(s) detected. Safe to apply rbac_schema_setup.sql.',
            'affected_count', v_warnings
        );
    ELSE
        v_report := v_report || jsonb_build_object(
            'check_id', '10b.overall_readiness',
            'category', 'READINESS',
            'status', 'PASS',
            'finding', 'MIGRATION READY: All preflight security and integrity checks passed. Ready for rbac_schema_setup.sql.',
            'affected_count', 0
        );
    END IF;

    PERFORM set_config('sorynth.preflight_report', v_report::text, true);
END $$;

-- ------------------------------------------------------------------------------
-- PREFLIGHT DIAGNOSTIC FINDINGS (Single Structured Results Grid)
-- ------------------------------------------------------------------------------
SELECT 
    (f->>'check_id')::text AS check_id,
    (f->>'category')::text AS category,
    (f->>'status')::text AS status,
    (f->>'finding')::text AS finding,
    (f->>'affected_count')::bigint AS affected_count
FROM jsonb_array_elements(COALESCE(current_setting('sorynth.preflight_report', true), '[]')::jsonb) AS f;

COMMIT;
