-- ==============================================================================
-- SORYNTH RESCUE COMMAND & DISPATCH CONSOLE
-- READ-ONLY EMERGENCY RECORDS PREVIEW BY CATEGORY & DEPENDENCIES
-- File: src/sql/preview_emergency_records_by_category.sql
-- Strictly non-destructive: Pure SELECT queries.
-- ==============================================================================

SELECT 
    e.id AS emergency_id,
    e.emergency_code,
    e.sender_name,
    e.sender_phone,
    e.status,
    ROUND(e.latitude::numeric, 4) AS latitude,
    ROUND(e.longitude::numeric, 4) AS longitude,
    e.custom_message,
    e.created_at,
    COUNT(DISTINCT u.id) AS linked_updates_count,
    COUNT(DISTINCT r.id) AS dependent_relay_logs_count,
    CASE 
        -- Category A: Operator Field Beacons (Preserved pending individual verification)
        WHEN e.sender_name = 'Operator Field Beacon' 
        THEN 'OPERATOR_FIELD_BEACON'

        -- Category B: Operator-Created / Interacted Dispatch Records (Preserved for operational history)
        WHEN e.emergency_code IN ('SOS-7861', 'TEST_NATURAL_DISASTER')
          OR (e.sender_name = 'Verified Dispatch Test')
        THEN 'OPERATOR_DISPATCH_RECORD'

        -- Category C: Confirmed Synthetic Test Records (Targeted for cleanup)
        WHEN e.emergency_code LIKE 'STATUS_TEST_%'
          OR e.emergency_code LIKE 'TYPE_TEST_%'
          OR e.emergency_code = 'TEST_LOST_STRANDED'
          OR e.emergency_code LIKE 'SOR_%'
          OR e.sender_name IN ('Status Tester', 'SORYNTH Live Verifier', 'SORYNTH Automated Verifier')
        THEN 'CONFIRMED_SYNTHETIC_TEST'

        -- Category D: Any other unverified record
        ELSE 'UNVERIFIED_RECORD'
    END AS classification_category,

    CASE 
        WHEN e.sender_name = 'Operator Field Beacon' 
        THEN 'PRESERVE_PENDING_MANUAL_REVIEW'

        WHEN e.emergency_code IN ('SOS-7861', 'TEST_NATURAL_DISASTER')
          OR (e.sender_name = 'Verified Dispatch Test')
        THEN 'PRESERVE_OPERATOR_DISPATCH_HISTORY'

        WHEN e.emergency_code LIKE 'STATUS_TEST_%'
          OR e.emergency_code LIKE 'TYPE_TEST_%'
          OR e.emergency_code = 'TEST_LOST_STRANDED'
          OR e.emergency_code LIKE 'SOR_%'
          OR e.sender_name IN ('Status Tester', 'SORYNTH Live Verifier', 'SORYNTH Automated Verifier')
        THEN 'ELIGIBLE_FOR_CLEANUP'

        ELSE 'PRESERVE_UNVERIFIED'
    END AS action_recommendation
FROM public.emergencies e
LEFT JOIN public.emergency_updates u ON u.emergency_id = e.id
LEFT JOIN public.relay_logs r ON r.emergency_id = e.id
GROUP BY 
    e.id, 
    e.emergency_code, 
    e.sender_name, 
    e.sender_phone, 
    e.status, 
    e.latitude, 
    e.longitude, 
    e.custom_message, 
    e.created_at
ORDER BY 
    CASE 
        WHEN e.sender_name = 'Operator Field Beacon' THEN 2
        WHEN e.emergency_code IN ('SOS-7861', 'TEST_NATURAL_DISASTER') THEN 3
        ELSE 1
    END,
    e.created_at DESC;
