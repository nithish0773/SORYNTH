-- ==============================================================================
-- SORYNTH REVIEWED SQL: HARDWARE LORA RELAY SECURITY & GATEWAY REGISTRY
-- File: src/sql/hardware_lora_relay_security.sql
-- ==============================================================================
-- Status: REVIEW ONLY (DO NOT EXECUTE UNTIL REVIEWED BY OPERATOR)
-- Purpose:
--   1. Permanently closes anonymous direct INSERT on public.relay_logs to prevent
--      unauthenticated table flooding, storage exhaustion, and packet spoofing.
--   2. Provisions public.lora_gateways: dedicated, hardened registry table storing
--      individual SHA-256 hashed gateway tokens with zero plaintext exposure.
--   3. Provides Super Admin RPCs to register, manage, and rotate gateway credentials.
--   4. Hardens ingest_lora_relay_packet (SECURITY DEFINER) with per-gateway SHA-256
--      authentication, physical RF telemetry validation, and emergency lifecycle checks.
--      (Completely removes shared global secret and Vault fallback).
--   5. Explicitly reaffirms EXECUTE permissions on mobile SOS and cancellation RPCs.
-- ==============================================================================

-- 0. PREREQUISITES: Ensure pgcrypto extension is active for SHA-256 digest
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. REVOKE ALL TABLE PRIVILEGES ON RELAY_LOGS FROM ANON, PUBLIC, AND CLIENT WRITES
-- Permanently closes live Supabase permission exposure: INSERT, SELECT, UPDATE, REFERENCES, TRIGGER, TRUNCATE.
-- Unauthenticated clients and general authenticated users must NEVER possess direct table write privileges.
REVOKE ALL PRIVILEGES ON public.relay_logs FROM anon, PUBLIC;
REVOKE ALL ON public.relay_logs FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.relay_logs FROM anon, PUBLIC;

REVOKE ALL PRIVILEGES ON public.relay_logs FROM authenticated;
REVOKE ALL ON public.relay_logs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.relay_logs FROM authenticated;
GRANT SELECT ON public.relay_logs TO authenticated;

-- 2. HARDEN RELAY_LOGS RLS POLICIES (ZERO DIRECT CLIENT INSERT)
-- Direct client table INSERT is completely prohibited.
-- Gateway packet ingestion is strictly routed through ingest_lora_relay_packet (SECURITY DEFINER)
-- or a verified server-side Edge Function.
ALTER TABLE public.relay_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Relay logs insert policy" ON public.relay_logs;
DROP POLICY IF EXISTS "Allow insert relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Insert relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Relay logs all policy" ON public.relay_logs;
DROP POLICY IF EXISTS "Allow read relay logs" ON public.relay_logs;

DROP POLICY IF EXISTS "Relay logs select policy" ON public.relay_logs;
CREATE POLICY "Relay logs select policy"
    ON public.relay_logs FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()) OR public.is_active_operator(auth.uid()));

-- 3. PROVISION HARDENED GATEWAY REGISTRY TABLE (public.lora_gateways)
-- Stores individual gateway identity, status, and SHA-256 token hash.
-- Plaintext tokens are NEVER stored, logged, or exposed.
CREATE TABLE IF NOT EXISTS public.lora_gateways (
    gateway_id VARCHAR(64) PRIMARY KEY,
    gateway_name TEXT NOT NULL,
    token_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'REVOKED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.now(),
    last_seen_at TIMESTAMPTZ,
    registered_by UUID,
    notes TEXT
);

-- Table-Level Security Lockdown: ZERO client access to anon or PUBLIC
ALTER TABLE public.lora_gateways ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON public.lora_gateways FROM anon, PUBLIC;
REVOKE ALL ON public.lora_gateways FROM anon, PUBLIC;
REVOKE ALL PRIVILEGES ON public.lora_gateways FROM authenticated;
REVOKE ALL ON public.lora_gateways FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.lora_gateways FROM authenticated;
GRANT SELECT ON public.lora_gateways TO authenticated;

-- Direct table access restricted to service_role only
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lora_gateways TO service_role;

-- Authenticated Super Admins can view gateways for fleet oversight
DROP POLICY IF EXISTS "Super Admins can view lora gateways" ON public.lora_gateways;
CREATE POLICY "Super Admins can view lora gateways"
    ON public.lora_gateways FOR SELECT
    TO authenticated
    USING (public.is_super_admin(auth.uid()));

-- 4. SUPER ADMIN GATEWAY MANAGEMENT RPCS (SECURITY DEFINER, search_path = '')

-- A. Register New LoRa Gateway (Plaintext token is hashed on ingestion and never persisted)
-- Automatic reactivation on conflict is strictly blocked; requires explicit status change.
CREATE OR REPLACE FUNCTION public.admin_register_lora_gateway(
    p_gateway_id VARCHAR(64),
    p_gateway_name TEXT,
    p_plaintext_token TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_existing_status TEXT;
BEGIN
    -- 1. Authorization Check: Super Admin only
    IF NOT public.is_super_admin(auth.uid()) THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Access Denied: Super Admin only');
    END IF;

    -- 2. Input Validation
    IF p_gateway_id IS NULL OR pg_catalog.trim(p_gateway_id) = '' THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Gateway ID cannot be empty');
    END IF;

    IF p_gateway_name IS NULL OR pg_catalog.trim(p_gateway_name) = '' THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Gateway name cannot be empty');
    END IF;

    IF p_plaintext_token IS NULL OR pg_catalog.length(p_plaintext_token) < 16 THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Gateway token must be at least 16 characters');
    END IF;

    -- 3. Duplicate Prevention & Explicit Reactivation Enforcement
    SELECT status INTO v_existing_status
    FROM public.lora_gateways
    WHERE gateway_id = p_gateway_id;

    IF FOUND THEN
        RETURN pg_catalog.jsonb_build_object(
            'success', false, 
            'error', 'Gateway already registered with status: ' || v_existing_status || '. Automatic reactivation is blocked. Use admin_set_lora_gateway_status or admin_rotate_lora_gateway_token.'
        );
    END IF;

    -- 4. Store One-Way SHA-256 Digest
    INSERT INTO public.lora_gateways (
        gateway_id, gateway_name, token_hash, status, registered_by, notes
    ) VALUES (
        p_gateway_id,
        p_gateway_name,
        pg_catalog.encode(extensions.digest(p_plaintext_token, 'sha256'), 'hex'),
        'ACTIVE',
        auth.uid(),
        p_notes
    );

    -- 5. Audit Log Event (Token is NEVER logged)
    PERFORM public.log_audit_event(
        'LORA_GATEWAY_REGISTERED',
        'lora_gateways',
        p_gateway_id,
        pg_catalog.jsonb_build_object('gateway_name', p_gateway_name, 'status', 'ACTIVE'),
        auth.uid()
    );

    RETURN pg_catalog.jsonb_build_object('success', true, 'gateway_id', p_gateway_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_register_lora_gateway(VARCHAR, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_register_lora_gateway(VARCHAR, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- B. Set Gateway Lifecycle Status (Explicit Super Admin operation for activation, suspension, revocation)
CREATE OR REPLACE FUNCTION public.admin_set_lora_gateway_status(
    p_gateway_id VARCHAR(64),
    p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_normalized_status TEXT;
    v_old_status TEXT;
BEGIN
    -- 1. Authorization Check: Super Admin only
    IF NOT public.is_super_admin(auth.uid()) THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Access Denied: Super Admin only');
    END IF;

    -- 2. Status Validation
    v_normalized_status := pg_catalog.upper(pg_catalog.trim(p_status));
    IF v_normalized_status NOT IN ('ACTIVE', 'SUSPENDED', 'REVOKED') THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Invalid status. Permitted: ACTIVE, SUSPENDED, REVOKED');
    END IF;

    -- 3. Gateway Existence Check
    SELECT status INTO v_old_status
    FROM public.lora_gateways
    WHERE gateway_id = p_gateway_id;

    IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Gateway not found');
    END IF;

    -- 4. Apply Status Transition
    UPDATE public.lora_gateways
    SET status = v_normalized_status
    WHERE gateway_id = p_gateway_id;

    -- 5. Audit Log Event
    PERFORM public.log_audit_event(
        'LORA_GATEWAY_STATUS_CHANGED',
        'lora_gateways',
        p_gateway_id,
        pg_catalog.jsonb_build_object('old_status', v_old_status, 'new_status', v_normalized_status),
        auth.uid()
    );

    RETURN pg_catalog.jsonb_build_object('success', true, 'gateway_id', p_gateway_id, 'status', v_normalized_status);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_lora_gateway_status(VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_lora_gateway_status(VARCHAR, TEXT) TO authenticated, service_role;

-- C. Rotate Gateway Token (One-way SHA-256 update with Super Admin authorization)
CREATE OR REPLACE FUNCTION public.admin_rotate_lora_gateway_token(
    p_gateway_id VARCHAR(64),
    p_new_plaintext_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_gateway_status TEXT;
BEGIN
    -- 1. Authorization Check: Super Admin only
    IF NOT public.is_super_admin(auth.uid()) THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Access Denied: Super Admin only');
    END IF;

    -- 2. Validate Token Strength
    IF p_new_plaintext_token IS NULL OR pg_catalog.length(p_new_plaintext_token) < 16 THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'New gateway token must be at least 16 characters');
    END IF;

    -- 3. Gateway Existence Check
    SELECT status INTO v_gateway_status
    FROM public.lora_gateways
    WHERE gateway_id = p_gateway_id;

    IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Gateway not found');
    END IF;

    -- 4. Apply New SHA-256 Digest
    UPDATE public.lora_gateways
    SET token_hash = pg_catalog.encode(extensions.digest(p_new_plaintext_token, 'sha256'), 'hex')
    WHERE gateway_id = p_gateway_id;

    -- 5. Audit Log Event (Token is NEVER logged)
    PERFORM public.log_audit_event(
        'LORA_GATEWAY_TOKEN_ROTATED',
        'lora_gateways',
        p_gateway_id,
        pg_catalog.jsonb_build_object('status', v_gateway_status),
        auth.uid()
    );

    RETURN pg_catalog.jsonb_build_object('success', true, 'gateway_id', p_gateway_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_rotate_lora_gateway_token(VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_rotate_lora_gateway_token(VARCHAR, TEXT) TO authenticated, service_role;

-- 5. PHASE 2: CONTROLLED GATEWAY INGESTION RPC (SECURITY DEFINER, search_path = '')
-- Physical ESP32 + LoRa gateways call this RPC using their assigned gateway_id and token.
CREATE OR REPLACE FUNCTION public.ingest_lora_relay_packet(
    p_emergency_id UUID,
    p_node_id VARCHAR(64),
    p_gateway_id VARCHAR(64),
    p_gateway_token TEXT,
    p_rssi INT DEFAULT NULL,
    p_snr DOUBLE PRECISION DEFAULT NULL,
    p_hop_number INT DEFAULT 1,
    p_payload_raw TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_expected_hash TEXT;
    v_gateway_status TEXT;
    v_emergency_status public.emergency_status_enum;
BEGIN
    -- 1. Gateway Authentication Check (Per-Gateway SHA-256 Hashed Token)
    -- Strictly requires gateway_id and token; zero shared-token or global Vault fallback
    IF p_gateway_id IS NULL OR p_gateway_token IS NULL OR pg_catalog.length(p_gateway_token) < 8 THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Unauthorized LoRa Gateway: Missing credentials');
    END IF;

    -- Look up active gateway credential
    SELECT token_hash, status INTO v_expected_hash, v_gateway_status
    FROM public.lora_gateways
    WHERE gateway_id = p_gateway_id;

    IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Unauthorized LoRa Gateway: Unregistered gateway ID');
    END IF;

    -- Strictly reject REVOKED or SUSPENDED gateways
    IF v_gateway_status != 'ACTIVE' THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Unauthorized LoRa Gateway: Gateway is ' || v_gateway_status);
    END IF;

    -- Validate SHA-256 digest (constant-length 64-char hex comparison)
    IF v_expected_hash IS DISTINCT FROM pg_catalog.encode(extensions.digest(p_gateway_token, 'sha256'), 'hex') THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Unauthorized LoRa Gateway: Invalid token');
    END IF;

    -- Update gateway heartbeat timestamp
    UPDATE public.lora_gateways
    SET last_seen_at = pg_catalog.clock_timestamp()
    WHERE gateway_id = p_gateway_id;

    -- 2. Validate emergency existence and active lifecycle status
    SELECT status INTO v_emergency_status 
    FROM public.emergencies 
    WHERE id = p_emergency_id;
    
    IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Referenced emergency record not found');
    END IF;

    IF v_emergency_status IN ('RESOLVED', 'CANCELLED') THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Emergency is already resolved or cancelled');
    END IF;

    -- 3. Physical RF Telemetry Bounds Sanity Check
    IF (p_rssi IS NOT NULL AND (p_rssi < -145 OR p_rssi > 0)) OR
       (p_snr IS NOT NULL AND (p_snr < -30.0 OR p_snr > 30.0)) OR
       (p_hop_number < 1 OR p_hop_number > 16) OR
       (pg_catalog.length(p_node_id) < 3) THEN
        RETURN pg_catalog.jsonb_build_object('success', false, 'error', 'Physical RF telemetry values out of physical bounds');
    END IF;

    -- 4. Secure Insert into relay_logs under Definer Privileges
    INSERT INTO public.relay_logs (
        emergency_id, node_id, gateway_id, rssi, snr, hop_number, payload_raw, received_at
    ) VALUES (
        p_emergency_id, p_node_id, p_gateway_id, p_rssi, p_snr, p_hop_number, p_payload_raw, pg_catalog.clock_timestamp()
    );

    RETURN pg_catalog.jsonb_build_object('success', true);
END;
$$;

-- Allow Gateway clients (anon or authenticated) to invoke the validated ingest RPC
GRANT EXECUTE ON FUNCTION public.ingest_lora_relay_packet(UUID, VARCHAR, VARCHAR, TEXT, INT, DOUBLE PRECISION, INT, TEXT) TO anon, authenticated;

-- 6. EXPLICIT EXECUTION PERMISSION CONFIRMATION FOR CITIZEN APIS
-- Guarantees mobile SOS and citizen cancellation remain accessible across all environments
-- Strictly targeting the exact signatures verified in SORYNTH-APK:
--   1. submit_sos_alert(character varying, text, text, text, text, double precision, double precision, double precision, text, integer, text[])
--   2. cancel_emergency(character varying, text)
--   3. get_emergency_status(character varying)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
          AND p.proname = 'submit_sos_alert'
          AND pg_get_function_identity_arguments(p.oid) = 'p_emergency_code character varying, p_sender_name text, p_sender_phone text, p_emergency_type text, p_custom_message text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_communication_method text, p_hop_count integer, p_relay_path text[]'
    ) THEN
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.submit_sos_alert(character varying, text, text, text, text, double precision, double precision, double precision, text, integer, text[]) TO anon, authenticated';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
          AND p.proname = 'cancel_emergency'
          AND pg_get_function_identity_arguments(p.oid) = 'p_emergency_code character varying, p_reason text'
    ) THEN
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.cancel_emergency(character varying, text) TO anon, authenticated';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' 
          AND p.proname = 'get_emergency_status'
          AND pg_get_function_identity_arguments(p.oid) = 'p_emergency_code character varying'
    ) THEN
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.get_emergency_status(character varying) TO anon, authenticated';
    END IF;
END $$;
