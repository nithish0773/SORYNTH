-- ==============================================================================
-- SORYNTH RESCUE COMMAND - ROLLBACK SCRIPT: HARDWARE LORA RELAY & GATEWAY REGISTRY
-- File: src/sql/rollback_hardware_lora_relay_security.sql
-- ==============================================================================
-- Status: ROLLBACK PLAN ONLY (Execute ONLY if reverting hardware_lora_relay_security.sql)
-- Guarantees:
--   1. Reverts gateway registry table and associated gateway admin RPCs.
--   2. Preserves public.relay_logs table, schema, and existing packet logs intact.
--   3. Preserves all citizen SOS RPCs and RBAC schema configurations.
-- ==============================================================================

BEGIN;

-- 1. DROP GATEWAY MANAGEMENT RPCS
DROP FUNCTION IF EXISTS public.admin_register_lora_gateway(VARCHAR, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_set_lora_gateway_status(VARCHAR, TEXT);
DROP FUNCTION IF EXISTS public.admin_rotate_lora_gateway_token(VARCHAR, TEXT);

-- 2. DROP CONTROLLED INGESTION RPC
DROP FUNCTION IF EXISTS public.ingest_lora_relay_packet(UUID, VARCHAR, VARCHAR, TEXT, INT, DOUBLE PRECISION, INT, TEXT);

-- 3. REMOVE LORA_GATEWAYS TABLE & POLICIES
DROP POLICY IF EXISTS "Super Admins can view lora gateways" ON public.lora_gateways;
DROP TABLE IF EXISTS public.lora_gateways;

-- 4. PRESERVE RELAY_LOGS TABLE AND POLICIES INTACT
-- (Existing packet logs and SELECT policies on public.relay_logs remain untouched)

COMMIT;

