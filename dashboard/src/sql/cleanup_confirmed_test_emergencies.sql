-- ==============================================================================
-- SORYNTH RESCUE COMMAND - STRICT CLEANUP: CONFIRMED SYNTHETIC TEST RECORDS ONLY
-- File: src/sql/cleanup_confirmed_test_emergencies.sql
-- Description: Targeted, transactional deletion of ONLY the 17 individually
--              confirmed synthetic test fixtures and their 6 probe updates.
--
-- EXPLICIT PRESERVATION GUARANTEES:
-- 1. PRESERVES ALL 12 Operator Field Beacon records (including SOS-2189, SOS-9976, SOS-1403).
-- 2. PRESERVES SOS-7861 and TEST_NATURAL_DISASTER (contain operator dispatch/status history).
-- 3. DOES NOT use broad OR conditions; every targeted UUID is individually verified.
-- 4. Checks all foreign key dependencies before deletion (FK to relay_logs & emergency_updates).
-- 5. Wrapped in an atomic PL/pgSQL DO transaction with full rollback protection.
-- 6. AUDIT INTEGRITY: Dynamically resolves authenticated operator session or falls back
--    neutrally to 'Database Maintenance Script' with NULL role (zero fabricated roles/names).
-- 7. DO NOT EXECUTE without separate manual review and authorization.
-- ==============================================================================

DO $$
DECLARE
    v_target_emergency_count       INTEGER;
    v_synthetic_code_match_count   INTEGER;
    v_preserved_record_count       INTEGER;
    v_target_update_count          INTEGER;
    v_updates_belonging_to_targets INTEGER;
    v_target_relay_count           INTEGER;
    v_deleted_updates              INTEGER;
    v_deleted_emergencies          INTEGER;
    v_remaining_targets            INTEGER;

    -- Actor identity resolution variables (dynamic, verified schema)
    v_caller_id                    UUID := auth.uid();
    v_actor_name                   TEXT := NULL;
    v_actor_email                  TEXT := NULL;
    v_actor_role                   TEXT := NULL;

    -- ==========================================================================
    -- 1. TARGET ALLOWLIST: EXACTLY 17 INDIVIDUALLY CONFIRMED SYNTHETIC RECORDS
    -- ==========================================================================
    c_target_emergency_ids CONSTANT UUID[] := ARRAY[
        -- Automated Status Lifecycle Fixtures (9 records, sender: 'Status Tester', 0 updates)
        '75062c3e-105c-4e65-b93b-316a253270bd'::UUID, -- STATUS_TEST_CANCELLED
        'a37be0ed-c80e-4120-a311-1a3776f34a0e'::UUID, -- STATUS_TEST_RESOLVED
        '771f925c-a8af-43f2-8060-ad0395c1b7d2'::UUID, -- STATUS_TEST_IN_ACTION
        'b616a549-0893-4c8f-816a-963b1ddc0ea0'::UUID, -- STATUS_TEST_ACKNOWLEDGED
        '568b41af-5951-40c4-8ee6-d06ee5cac0d0'::UUID, -- STATUS_TEST_DELIVERED
        'da86161e-3ecd-4865-95c6-f99b76b529e9'::UUID, -- STATUS_TEST_RELAYED
        '908b8a20-6b86-4773-bae4-884950b58a4d'::UUID, -- STATUS_TEST_TRANSMITTING
        'c9e28c43-854b-44ea-b8a5-03844b970782'::UUID, -- STATUS_TEST_STORED
        '7c59c98e-57a6-4915-8719-451add2f7201'::UUID, -- STATUS_TEST_PENDING

        -- Automated Type & Category Fixtures (5 records, sender: null, 0 updates)
        '1ff04a86-7a77-4cdd-9143-b2a27d28b056'::UUID, -- TYPE_TEST_OTHER
        'a7e48542-550e-442c-8af5-c77c3df1e8e5'::UUID, -- TYPE_TEST_ACCIDENT
        '2ec438d9-3a91-4801-b8ae-8a48503e054a'::UUID, -- TYPE_TEST_FIRE
        '175eddec-ff74-409a-81ff-03778b0a5184'::UUID, -- TYPE_TEST_MEDICAL
        '7bd7f9db-8f1c-4210-a1e6-12a9f7fd7859'::UUID, -- TEST_LOST_STRANDED

        -- Automated Connectivity Probes (3 records, automated probe messages & cleanup)
        'e3d40c07-179b-465e-b3e1-f0a9b4a30954'::UUID, -- SOR_PROBE_1793824256
        'af6e503e-fc88-4005-b21f-473bde5fcbc4'::UUID, -- SOR_PROBE_1793824216
        '193a5082-572a-4f66-b5fb-a38772c8f4d2'::UUID  -- SOR_VERIFY_1793824105
    ];

    -- ==========================================================================
    -- 2. TARGET UPDATES ALLOWLIST: EXACTLY 6 AUTOMATED PROBE UPDATES
    -- ==========================================================================
    c_target_update_ids CONSTANT UUID[] := ARRAY[
        '848bfca7-b87f-4bd6-81c8-4540f8ab934c'::UUID, -- SOR_VERIFY_1793824105 (DELIVERED probe log)
        'eb2b3ca8-12c5-40e2-955f-4f6b9513d499'::UUID, -- SOR_VERIFY_1793824105 (CANCELLED probe cleanup)
        '08856bbe-bf66-4c26-9697-8d66c5907995'::UUID, -- SOR_PROBE_1793824216 (DELIVERED probe log)
        '4011d9ce-2cdc-40d3-96d7-45b220467131'::UUID, -- SOR_PROBE_1793824216 (CANCELLED probe cleanup)
        '2812c8a2-3d86-4bd9-b225-08b0075acb59'::UUID, -- SOR_PROBE_1793824256 (DELIVERED probe log)
        '04ded38e-caf6-479a-9206-5f717fbcbf33'::UUID  -- SOR_PROBE_1793824256 (CANCELLED probe cleanup)
    ];

    -- ==========================================================================
    -- 3. EXCLUSION SHIELD: 14 SPECIFICALLY PRESERVED RECORDS
    -- ==========================================================================
    c_preserved_emergency_ids CONSTANT UUID[] := ARRAY[
        -- Operator Field Beacons (12 records)
        'fd5481ad-abb4-4ca7-bbda-38e60a493818'::UUID, -- SOS-5654
        '5a8223c7-1fd1-4606-9f1a-02065eb208b2'::UUID, -- SOS-9976
        'd22436a8-4120-4cf4-ac4c-2eb7fb901f76'::UUID, -- SOS-1403
        'ee4ea066-908a-4d53-a2e4-3af02c20c5d7'::UUID, -- SOS-9146
        'eea94dc9-07fa-4012-b41a-7168eea355d2'::UUID, -- SOS-1568
        'af27ad7e-a860-4549-8cc4-9e9d84ccd6d1'::UUID, -- SOS-3473
        'f1012852-ae2a-4774-a4bb-4bd2ee707cff'::UUID, -- SOS-6041
        'c6400bba-0c3c-4d4d-80c3-044cc3cf6247'::UUID, -- SOS-4898
        'a734425a-dcd9-4cd7-a5e6-a6e92d0d7945'::UUID, -- SOS-3263
        '6983de5f-8d47-4bdd-8d4f-e7c59054b137'::UUID, -- SOS-4500
        'c0045f51-0b53-43dc-a0fe-21042c48f476'::UUID, -- SOS-2189
        'e238157c-873e-487e-95e4-b03992fcfe1b'::UUID, -- SOS-4462

        -- Operator Dispatch & History Records (2 records)
        'f15df299-425e-424b-b4e3-f6c24f7b8592'::UUID, -- SOS-7861
        'e879793b-e423-428f-9dbe-afd3649c4d6b'::UUID  -- TEST_NATURAL_DISASTER
    ];

BEGIN
    -- --------------------------------------------------------------------------
    -- SAFETY CHECK 1: EXACT MATCH COUNT ON SYNTHETIC EMERGENCY ALLOWLIST
    -- --------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_target_emergency_count
    FROM public.emergencies
    WHERE id = ANY(c_target_emergency_ids);

    IF v_target_emergency_count <> 17 THEN
        RAISE EXCEPTION 'SAFETY CHECK 1 FAILED: Expected exactly 17 synthetic emergencies, but found %. Aborting.', v_target_emergency_count;
    END IF;

    -- --------------------------------------------------------------------------
    -- SAFETY CHECK 2: PRESERVATION SHIELD ASSERTION
    -- Guarantees ZERO preserved records appear in the deletion target allowlist
    -- --------------------------------------------------------------------------
    IF c_target_emergency_ids && c_preserved_emergency_ids THEN
        RAISE EXCEPTION 'SAFETY CHECK 2 FAILED: Deletion allowlist collides with preserved emergency IDs. Aborting.';
    END IF;

    -- Verify that all 14 preserved records remain intact in the database
    SELECT COUNT(*) INTO v_preserved_record_count
    FROM public.emergencies
    WHERE id = ANY(c_preserved_emergency_ids);

    IF v_preserved_record_count <> 14 THEN
        RAISE EXCEPTION 'SAFETY CHECK 2 FAILED: Expected 14 preserved records in database, but found %. Aborting.', v_preserved_record_count;
    END IF;

    -- --------------------------------------------------------------------------
    -- SAFETY CHECK 3: INDIVIDUAL CODE PATTERN VERIFICATION ON ALL 17 TARGETS
    -- Every targeted record MUST have an unambiguous synthetic test code prefix
    -- --------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_synthetic_code_match_count
    FROM public.emergencies
    WHERE id = ANY(c_target_emergency_ids)
      AND (
          emergency_code LIKE 'STATUS_TEST_%'
          OR emergency_code LIKE 'TYPE_TEST_%'
          OR emergency_code = 'TEST_LOST_STRANDED'
          OR emergency_code LIKE 'SOR_PROBE_%'
          OR emergency_code LIKE 'SOR_VERIFY_%'
      );

    IF v_synthetic_code_match_count <> 17 THEN
        RAISE EXCEPTION 'SAFETY CHECK 3 FAILED: Expected all 17 targets to have synthetic code prefixes, but only % matched. Aborting.', v_synthetic_code_match_count;
    END IF;

    -- --------------------------------------------------------------------------
    -- SAFETY CHECK 4: EXACT MATCH COUNT ON TARGET UPDATES ALLOWLIST
    -- --------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_target_update_count
    FROM public.emergency_updates
    WHERE id = ANY(c_target_update_ids);

    IF v_target_update_count <> 6 THEN
        RAISE EXCEPTION 'SAFETY CHECK 4 FAILED: Expected exactly 6 probe updates, but found %. Aborting.', v_target_update_count;
    END IF;

    -- --------------------------------------------------------------------------
    -- SAFETY CHECK 5: UPDATES INTEGRITY & FOREIGN KEY CROSS-CHECK
    -- All 6 updates must belong exclusively to target probe emergencies
    -- --------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_updates_belonging_to_targets
    FROM public.emergency_updates
    WHERE id = ANY(c_target_update_ids)
      AND emergency_id = ANY(c_target_emergency_ids);

    IF v_updates_belonging_to_targets <> 6 THEN
        RAISE EXCEPTION 'SAFETY CHECK 5 FAILED: Expected all 6 updates to link to target probe emergencies, but found %. Aborting.', v_updates_belonging_to_targets;
    END IF;

    -- Verify no target emergency has extraneous unlisted updates
    IF EXISTS (
        SELECT 1 FROM public.emergency_updates
        WHERE emergency_id = ANY(c_target_emergency_ids)
          AND id <> ALL(c_target_update_ids)
    ) THEN
        RAISE EXCEPTION 'SAFETY CHECK 5 FAILED: Found extraneous updates referencing target emergencies. Aborting.';
    END IF;

    -- --------------------------------------------------------------------------
    -- SAFETY CHECK 6: ZERO DEPENDENT ROWS IN RELAY_LOGS
    -- --------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_target_relay_count
    FROM public.relay_logs
    WHERE emergency_id = ANY(c_target_emergency_ids);

    IF v_target_relay_count > 0 THEN
        RAISE EXCEPTION 'SAFETY CHECK 6 FAILED: Found % relay_logs referencing target emergencies. Aborting.', v_target_relay_count;
    END IF;

    -- --------------------------------------------------------------------------
    -- STEP 7: DELETE CHILD RECORDS FIRST (6 probe updates)
    -- --------------------------------------------------------------------------
    WITH deleted_u AS (
        DELETE FROM public.emergency_updates
        WHERE id = ANY(c_target_update_ids)
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted_updates FROM deleted_u;

    IF v_deleted_updates <> 6 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected to delete 6 updates, but deleted %. Rolling back.', v_deleted_updates;
    END IF;

    -- --------------------------------------------------------------------------
    -- STEP 8: DELETE PARENT RECORDS (17 synthetic emergencies)
    -- --------------------------------------------------------------------------
    WITH deleted_e AS (
        DELETE FROM public.emergencies
        WHERE id = ANY(c_target_emergency_ids)
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted_emergencies FROM deleted_e;

    IF v_deleted_emergencies <> 17 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Expected to delete 17 emergencies, but deleted %. Rolling back.', v_deleted_emergencies;
    END IF;

    -- --------------------------------------------------------------------------
    -- STEP 9: POST-DELETE ZERO-RESIDUAL ASSERTION
    -- --------------------------------------------------------------------------
    SELECT COUNT(*) INTO v_remaining_targets
    FROM public.emergencies
    WHERE id = ANY(c_target_emergency_ids);

    IF v_remaining_targets <> 0 THEN
        RAISE EXCEPTION 'ASSERTION FAILED: Residual target emergencies detected (%). Rolling back.', v_remaining_targets;
    END IF;

    -- --------------------------------------------------------------------------
    -- STEP 10: WRITE AUDIT LOG ENTRY (Verified Schema Alignment & Safe Actor Lookup)
    -- --------------------------------------------------------------------------
    -- Safely derive authenticated actor from database if an active session exists
    IF v_caller_id IS NOT NULL THEN
        SELECT full_name, email, role 
        INTO v_actor_name, v_actor_email, v_actor_role
        FROM public.operator_profiles 
        WHERE user_id = v_caller_id
        LIMIT 1;

        -- If not found in operator_profiles, safely check profiles
        IF v_actor_name IS NULL THEN
            SELECT full_name, email 
            INTO v_actor_name, v_actor_email
            FROM public.profiles 
            WHERE id = v_caller_id
            LIMIT 1;
        END IF;
    END IF;

    -- If no authenticated operator session is present, record truthful maintenance identity without inventing a role
    IF v_actor_name IS NULL THEN
        v_actor_name := 'Database Maintenance Script';
        v_actor_role := NULL;
        v_actor_email := NULL;
    END IF;

    INSERT INTO public.audit_logs (
        action,
        entity_type,
        entity_id,
        actor_id,
        actor_email,
        actor_name,
        actor_role,
        details,
        created_at
    ) VALUES (
        'CLEANUP_CONFIRMED_SYNTHETIC_TEST_EMERGENCIES',
        'emergencies',
        'BATCH_17_SYNTHETIC_TEST_EMERGENCIES',
        v_caller_id,
        v_actor_email,
        v_actor_name,
        v_actor_role,
        jsonb_build_object(
            'deleted_emergencies_count', v_deleted_emergencies,
            'deleted_updates_count', v_deleted_updates,
            'preserved_emergencies_count', v_preserved_record_count,
            'reason', 'Purged confirmed synthetic unit test fixtures and connectivity probe records'
        ),
        NOW()
    );

    RAISE NOTICE 'SUCCESS: Successfully deleted % confirmed synthetic test emergencies and % probe updates. 14 operator/beacon records preserved.',
        v_deleted_emergencies, v_deleted_updates;

END $$;
