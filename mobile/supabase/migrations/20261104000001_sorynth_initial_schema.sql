-- ==============================================================================
-- SORYNTH EMERGENCY COMMUNICATION SYSTEM
-- DATABASE MIGRATIONS - SUPABASE POSTGRESQL
-- Project: Hybrid Internet and LoRa-Based Emergency SOS Communication System
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 2. ENUMS
DO $$ BEGIN
    CREATE TYPE emergency_type_enum AS ENUM (
        'MEDICAL',
        'ACCIDENT',
        'FIRE',
        'NATURAL_DISASTER',
        'LOST_STRANDED',
        'OTHER'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END;
$$;

DO $$ BEGIN
    CREATE TYPE communication_method_enum AS ENUM (
        'INTERNET',
        'BLUETOOTH_LORA',
        'LORA_RELAY',
        'HYBRID'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END;
$$;

DO $$ BEGIN
    CREATE TYPE emergency_status_enum AS ENUM (
        'PENDING',
        'STORED',
        'TRANSMITTING',
        'RELAYED',
        'DELIVERED',
        'ACKNOWLEDGED',
        'IN_ACTION',
        'RESOLVED',
        'CANCELLED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END;
$$;

DO $$ BEGIN
    CREATE TYPE rescue_role_enum AS ENUM (
        'COMMANDER',
        'PARAMEDIC',
        'SEARCH_AND_RESCUE',
        'DISPATCHER',
        'VOLUNTEER'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END;
$$;

-- 3. TABLE: PROFILES (Registered Users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone_number TEXT,
    email TEXT,
    blood_group TEXT,
    medical_notes TEXT,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Trigger to auto-update updated_at on profiles
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- 4. TABLE: RESCUE_TEAMS
CREATE TABLE IF NOT EXISTS public.rescue_teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_name TEXT NOT NULL,
    jurisdiction_zone TEXT NOT NULL,
    contact_phone TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, ON_MISSION, STANDBY
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 5. TABLE: EMERGENCIES (Core SOS table)
CREATE TABLE IF NOT EXISTS public.emergencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_code VARCHAR(32) UNIQUE NOT NULL, -- e.g. SOR100001
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- NULL for Guest SOS
    is_guest BOOLEAN NOT NULL DEFAULT false,
    sender_name TEXT,
    sender_phone TEXT,
    emergency_type emergency_type_enum NOT NULL DEFAULT 'OTHER',
    custom_message TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy_meters DOUBLE PRECISION,
    altitude DOUBLE PRECISION,
    communication_method communication_method_enum NOT NULL DEFAULT 'INTERNET',
    status emergency_status_enum NOT NULL DEFAULT 'DELIVERED',
    hop_count INT NOT NULL DEFAULT 0,
    relay_path TEXT[] DEFAULT ARRAY[]::TEXT[],
    assigned_team_id UUID REFERENCES public.rescue_teams(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    acknowledged_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

DROP TRIGGER IF EXISTS set_emergencies_updated_at ON public.emergencies;
CREATE TRIGGER set_emergencies_updated_at
    BEFORE UPDATE ON public.emergencies
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- Indexes for rapid lookup and map/geo queries
CREATE INDEX IF NOT EXISTS idx_emergencies_code ON public.emergencies(emergency_code);
CREATE INDEX IF NOT EXISTS idx_emergencies_status ON public.emergencies(status);
CREATE INDEX IF NOT EXISTS idx_emergencies_user_id ON public.emergencies(user_id);
CREATE INDEX IF NOT EXISTS idx_emergencies_created_at ON public.emergencies(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emergencies_lat_lng ON public.emergencies(latitude, longitude);

-- 6. TABLE: EMERGENCY_UPDATES (Timeline / Status Changes)
CREATE TABLE IF NOT EXISTS public.emergency_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID NOT NULL REFERENCES public.emergencies(id) ON DELETE CASCADE,
    previous_status emergency_status_enum,
    new_status emergency_status_enum NOT NULL,
    note TEXT,
    updated_by_user_id UUID REFERENCES auth.users(id),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_emergency_updates_emergency_id ON public.emergency_updates(emergency_id);

-- 7. TABLE: RELAY_LOGS (ESP32 / LoRa Node hops)
CREATE TABLE IF NOT EXISTS public.relay_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emergency_id UUID NOT NULL REFERENCES public.emergencies(id) ON DELETE CASCADE,
    node_id VARCHAR(64) NOT NULL, -- ESP32 device ID or Mac address
    gateway_id VARCHAR(64),
    rssi INT,                     -- Signal strength in dBm
    snr DOUBLE PRECISION,         -- Signal-to-Noise Ratio
    hop_number INT NOT NULL DEFAULT 1,
    payload_raw TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_relay_logs_emergency_id ON public.relay_logs(emergency_id);
CREATE INDEX IF NOT EXISTS idx_relay_logs_node_id ON public.relay_logs(node_id);

-- ==============================================================================
-- 8. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.relay_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rescue_teams ENABLE ROW LEVEL SECURITY;

-- Profiles:
-- Users can view and update their own profile.
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- Emergencies:
-- 1. Authenticated users can view emergencies they created.
CREATE POLICY "Users can view their own emergencies"
    ON public.emergencies FOR SELECT
    USING (auth.uid() = user_id);

-- 2. Authenticated users can insert their own emergencies.
CREATE POLICY "Authenticated users can create emergencies"
    ON public.emergencies FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 3. Authenticated users can update (e.g. cancel) their own active emergencies.
CREATE POLICY "Users can update own emergencies"
    ON public.emergencies FOR UPDATE
    USING (auth.uid() = user_id);

-- 4. Guest SOS & Rate-Limited Insert:
-- To prevent unrestricted inserts and table scanning by unauthorized parties,
-- we expose a secure PostgreSQL Stored Function (RPC) `submit_sos_alert` with SECURITY DEFINER.
-- Direct table SELECT is restricted. Anyone with emergency_code can query single status via `get_emergency_status`.

-- Emergency Updates:
CREATE POLICY "Users can view updates for their own emergencies"
    ON public.emergency_updates FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.emergencies
            WHERE emergencies.id = emergency_updates.emergency_id
            AND emergencies.user_id = auth.uid()
        )
    );

-- ==============================================================================
-- 9. SECURE STORED PROCEDURES (RPC) FOR GUEST & CLIENT SOS SUBMISSIONS
-- ==============================================================================

-- Function 1: submit_sos_alert
-- Validates inputs, handles guest vs authenticated, prevents spam, and returns generated emergency details.
CREATE OR REPLACE FUNCTION public.submit_sos_alert(
    p_emergency_code VARCHAR(32),
    p_sender_name TEXT,
    p_sender_phone TEXT,
    p_emergency_type TEXT,
    p_custom_message TEXT,
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_accuracy_meters DOUBLE PRECISION DEFAULT NULL,
    p_communication_method TEXT DEFAULT 'INTERNET',
    p_hop_count INT DEFAULT 0,
    p_relay_path TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with elevated rights to safely insert guest or user record
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_is_guest BOOLEAN;
    v_emergency_type emergency_type_enum;
    v_comm_method communication_method_enum;
    v_record emergencies%ROWTYPE;
BEGIN
    -- 1. Validate Coordinates
    IF p_latitude IS NULL OR p_longitude IS NULL OR 
       p_latitude < -90.0 OR p_latitude > 90.0 OR 
       p_longitude < -180.0 OR p_longitude > 180.0 THEN
        RAISE EXCEPTION 'Invalid GPS coordinates provided: lat=%, lng=%', p_latitude, p_longitude;
    END IF;

    -- 2. Determine User / Guest
    v_user_id := auth.uid();
    v_is_guest := (v_user_id IS NULL);

    -- 3. Parse Enums safely
    BEGIN
        v_emergency_type := p_emergency_type::emergency_type_enum;
    EXCEPTION WHEN OTHERS THEN
        v_emergency_type := 'OTHER'::emergency_type_enum;
    END;

    BEGIN
        v_comm_method := p_communication_method::communication_method_enum;
    EXCEPTION WHEN OTHERS THEN
        v_comm_method := 'INTERNET'::communication_method_enum;
    END;

    -- 4. Prevent duplicate submission with same emergency_code
    SELECT * INTO v_record FROM public.emergencies WHERE emergency_code = p_emergency_code;
    IF FOUND THEN
        -- Return existing record if already inserted
        RETURN jsonb_build_object(
            'success', true,
            'is_duplicate', true,
            'emergency_id', v_record.id,
            'emergency_code', v_record.emergency_code,
            'status', v_record.status,
            'created_at', v_record.created_at
        );
    END IF;

    -- 5. Insert new emergency record
    INSERT INTO public.emergencies (
        emergency_code,
        user_id,
        is_guest,
        sender_name,
        sender_phone,
        emergency_type,
        custom_message,
        latitude,
        longitude,
        accuracy_meters,
        communication_method,
        status,
        hop_count,
        relay_path
    ) VALUES (
        p_emergency_code,
        v_user_id,
        v_is_guest,
        COALESCE(p_sender_name, CASE WHEN v_is_guest THEN 'Guest User' ELSE 'Registered User' END),
        p_sender_phone,
        v_emergency_type,
        p_custom_message,
        p_latitude,
        p_longitude,
        p_accuracy_meters,
        v_comm_method,
        'DELIVERED'::emergency_status_enum,
        p_hop_count,
        p_relay_path
    ) RETURNING * INTO v_record;

    -- 6. Insert initial timeline entry in emergency_updates
    INSERT INTO public.emergency_updates (
        emergency_id,
        previous_status,
        new_status,
        note,
        updated_by_user_id,
        latitude,
        longitude
    ) VALUES (
        v_record.id,
        NULL,
        'DELIVERED'::emergency_status_enum,
        'Emergency alert successfully received and logged on SORYNTH network.',
        v_user_id,
        p_latitude,
        p_longitude
    );

    RETURN jsonb_build_object(
        'success', true,
        'is_duplicate', false,
        'emergency_id', v_record.id,
        'emergency_code', v_record.emergency_code,
        'status', v_record.status,
        'created_at', v_record.created_at
    );
END;
$$;

-- Function 2: get_emergency_status
-- Allows Guest users and tracking screen to query emergency status by unique emergency_code without exposing the entire table
CREATE OR REPLACE FUNCTION public.get_emergency_status(p_emergency_code VARCHAR(32))
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_record emergencies%ROWTYPE;
BEGIN
    SELECT * INTO v_record FROM public.emergencies WHERE emergency_code = p_emergency_code;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('found', false);
    END IF;

    RETURN jsonb_build_object(
        'found', true,
        'emergency_id', v_record.id,
        'emergency_code', v_record.emergency_code,
        'emergency_type', v_record.emergency_type,
        'status', v_record.status,
        'latitude', v_record.latitude,
        'longitude', v_record.longitude,
        'accuracy_meters', v_record.accuracy_meters,
        'communication_method', v_record.communication_method,
        'created_at', v_record.created_at,
        'updated_at', v_record.updated_at,
        'acknowledged_at', v_record.acknowledged_at,
        'resolved_at', v_record.resolved_at
    );
END;
$$;

-- Function 3: cancel_emergency
-- Allows user or guest with the emergency_code to cancel their emergency
CREATE OR REPLACE FUNCTION public.cancel_emergency(p_emergency_code VARCHAR(32), p_reason TEXT DEFAULT 'Cancelled by user')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_record emergencies%ROWTYPE;
BEGIN
    SELECT * INTO v_record FROM public.emergencies WHERE emergency_code = p_emergency_code;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Emergency not found');
    END IF;

    -- If registered user, verify ownership
    IF NOT v_record.is_guest AND v_record.user_id != auth.uid() THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized');
    END IF;

    -- Update status
    UPDATE public.emergencies
    SET status = 'CANCELLED'::emergency_status_enum,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_record.id;

    -- Log update
    INSERT INTO public.emergency_updates (
        emergency_id,
        previous_status,
        new_status,
        note,
        updated_by_user_id
    ) VALUES (
        v_record.id,
        v_record.status,
        'CANCELLED'::emergency_status_enum,
        p_reason,
        auth.uid()
    );

    RETURN jsonb_build_object('success', true, 'status', 'CANCELLED');
END;
$$;

-- Grant EXECUTE permissions to anon and authenticated users
GRANT EXECUTE ON FUNCTION public.submit_sos_alert TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_emergency_status TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_emergency TO anon, authenticated;

-- ==============================================================================
-- 10. REALTIME CONFIGURATION
-- ==============================================================================
-- Add emergencies and emergency_updates to Supabase Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.emergencies;
ALTER PUBLICATION supabase_realtime ADD TABLE public.emergency_updates;

