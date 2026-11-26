-- ==============================================================================
-- SORYNTH RESCUE COMMAND & DISPATCH CONSOLE
-- READ-ONLY EMERGENCY RECORDS COMPREHENSIVE AUDIT SCRIPT
-- File: src/sql/audit_test_emergencies_read_only.sql
-- ==============================================================================
-- GUARANTEES:
-- 1. Strictly READ-ONLY: Pure SELECT statements with zero DDL, DML, or mutations.
-- 2. Fully safe to execute in Supabase SQL Editor, psql, or via Supabase CLI.
-- 3. Categorizes all 31 records into exact test beacon matches vs other test artifacts.
-- 4. Counts linked emergency_updates rows per record to evaluate foreign key relations.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- QUERY 1: DETAILED AUDIT INVENTORY OF ALL 31 EMERGENCY RECORDS
-- ------------------------------------------------------------------------------
WITH classified_emergencies AS (
    SELECT 
        e.id,
        e.emergency_code,
        e.sender_name,
        e.sender_phone,
        ROUND(e.latitude::numeric, 4) AS latitude,
        ROUND(e.longitude::numeric, 4) AS longitude,
        e.status,
        e.emergency_type,
        e.communication_method,
        e.custom_message,
        e.created_at,
        COUNT(u.id) AS linked_updates_count,
        CASE 
            -- Pattern A: Confirmed Command Map Quick Dispatch Test Beacons
            WHEN e.sender_name = 'Operator Field Beacon' 
              OR e.sender_phone = '+91 98800 12345' 
              OR e.custom_message ILIKE '%Command Map%' 
              OR e.custom_message ILIKE '%Tactical emergency beacon%'
            THEN 'CONFIRMED_MAP_TEST_BEACON'

            -- Pattern B: Confirmed Automated Connectivity Probes
            WHEN e.emergency_code LIKE 'SOR_PROBE_%' 
              OR e.emergency_code LIKE 'SOR_VERIFY_%'
              OR e.sender_name ILIKE '%Verifier%'
              OR e.sender_phone = '+910000000000'
              OR e.custom_message ILIKE '%connectivity verification probe%'
            THEN 'CONFIRMED_CONNECTIVITY_PROBE'

            -- Pattern C: Confirmed Automated Unit/Lifecycle Test Fixtures
            WHEN e.emergency_code LIKE 'STATUS_TEST_%'
              OR e.emergency_code LIKE 'TYPE_TEST_%'
              OR e.emergency_code LIKE 'TEST_%'
              OR e.sender_name = 'Status Tester'
              OR e.sender_name = 'Verified Dispatch Test'
              OR e.custom_message ILIKE '%verified test beacon%'
            THEN 'CONFIRMED_UNIT_TEST_FIXTURE'

            -- Pattern D: Uncertain or Genuine Citizen Emergency Records
            ELSE 'UNCERTAIN_OR_GENUINE'
        END AS audit_category,

        ARRAY_TO_STRING(ARRAY[
            CASE WHEN e.sender_name = 'Operator Field Beacon' THEN 'sender="Operator Field Beacon"' END,
            CASE WHEN e.sender_phone = '+91 98800 12345' THEN 'phone="+91 98800 12345"' END,
            CASE WHEN e.custom_message ILIKE '%Command Map%' THEN 'msg="Command Map beacon"' END,
            CASE WHEN e.emergency_code LIKE 'STATUS_TEST_%' THEN 'code=STATUS_TEST' END,
            CASE WHEN e.emergency_code LIKE 'TYPE_TEST_%' THEN 'code=TYPE_TEST' END,
            CASE WHEN e.emergency_code LIKE 'TEST_%' THEN 'code=TEST_CAT' END,
            CASE WHEN e.emergency_code LIKE 'SOR_%' THEN 'code=SOR_PROBE' END,
            CASE WHEN e.sender_phone = '+910000000000' THEN 'phone=probe_placeholder' END,
            CASE WHEN e.sender_name = 'Verified Dispatch Test' THEN 'sender=Verified Dispatch Test' END
        ], '; ') AS matched_indicators
    FROM public.emergencies e
    LEFT JOIN public.emergency_updates u ON u.emergency_id = e.id
    GROUP BY 
        e.id, 
        e.emergency_code, 
        e.sender_name, 
        e.sender_phone, 
        e.latitude, 
        e.longitude, 
        e.status, 
        e.emergency_type, 
        e.communication_method, 
        e.custom_message, 
        e.created_at
)
SELECT 
    id,
    emergency_code,
    sender_name,
    sender_phone,
    latitude,
    longitude,
    status,
    emergency_type,
    communication_method,
    custom_message,
    created_at,
    linked_updates_count,
    audit_category,
    matched_indicators
FROM classified_emergencies
ORDER BY 
    CASE audit_category 
        WHEN 'CONFIRMED_MAP_TEST_BEACON' THEN 1
        WHEN 'CONFIRMED_UNIT_TEST_FIXTURE' THEN 2
        WHEN 'CONFIRMED_CONNECTIVITY_PROBE' THEN 3
        ELSE 4
    END,
    created_at DESC;

-- ------------------------------------------------------------------------------
-- QUERY 2: SUMMARY AGGREGATION BY AUDIT CATEGORY AND LIFECYCLE STATUS
-- ------------------------------------------------------------------------------
SELECT 
    CASE 
        WHEN e.sender_name = 'Operator Field Beacon' 
          OR e.sender_phone = '+91 98800 12345' 
          OR e.custom_message ILIKE '%Command Map%' 
          OR e.custom_message ILIKE '%Tactical emergency beacon%'
        THEN 'CONFIRMED_MAP_TEST_BEACON'

        WHEN e.emergency_code LIKE 'SOR_PROBE_%' 
          OR e.emergency_code LIKE 'SOR_VERIFY_%'
          OR e.sender_name ILIKE '%Verifier%'
          OR e.sender_phone = '+910000000000'
          OR e.custom_message ILIKE '%connectivity verification probe%'
        THEN 'CONFIRMED_CONNECTIVITY_PROBE'

        WHEN e.emergency_code LIKE 'STATUS_TEST_%'
          OR e.emergency_code LIKE 'TYPE_TEST_%'
          OR e.emergency_code LIKE 'TEST_%'
          OR e.sender_name = 'Status Tester'
          OR e.sender_name = 'Verified Dispatch Test'
          OR e.custom_message ILIKE '%verified test beacon%'
        THEN 'CONFIRMED_UNIT_TEST_FIXTURE'

        ELSE 'UNCERTAIN_OR_GENUINE'
    END AS audit_category,
    COUNT(DISTINCT e.id) AS emergency_count,
    COUNT(DISTINCT CASE WHEN e.status IN ('PENDING', 'STORED', 'TRANSMITTING', 'RELAYED', 'DELIVERED', 'ACKNOWLEDGED', 'IN_ACTION') THEN e.id END) AS active_count,
    COUNT(DISTINCT CASE WHEN e.status = 'RESOLVED' THEN e.id END) AS resolved_count,
    COUNT(DISTINCT CASE WHEN e.status IN ('CANCELLED', 'FAILED') THEN e.id END) AS cancelled_count,
    COUNT(u.id) AS total_linked_updates
FROM public.emergencies e
LEFT JOIN public.emergency_updates u ON u.emergency_id = e.id
GROUP BY 1
ORDER BY emergency_count DESC;
