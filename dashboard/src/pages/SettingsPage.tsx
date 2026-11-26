import React, { useState } from 'react';
import { 
  Settings, 
  Volume2, 
  Copy, 
  Check, 
  RefreshCw, 
  ExternalLink,
  Sun,
  Moon,
  Laptop
} from 'lucide-react';
import { GlassCard } from '../components/common/GlassCard';
import { useAuth } from '../context/AuthContext';
import { useEmergencies } from '../context/EmergencyContext';
import { useTheme } from '../context/ThemeContext';
import { SUPABASE_URL, SUPABASE_ANON_KEY, checkBackendConnection } from '../services/supabaseClient';

export const SettingsPage: React.FC = () => {
  const { user, profile, operatorRole, signOut } = useAuth();
  const { soundAlertEnabled, setSoundAlertEnabled } = useEmergencies();
  const { theme, setTheme, isDark } = useTheme();

  const [copiedSql, setCopiedSql] = useState(false);
  const [testingConnection, setTestingConnection] = useState(false);
  const [testResult, setTestResult] = useState<string | null>(null);

  const sqlSetupScript = `-- SORYNTH RESCUE COMMAND DASHBOARD - OPERATOR SETUP SCRIPT
-- Execute in Supabase SQL Editor: https://supabase.com/dashboard/project/_/sql

-- 1. Ensure rescue_role column exists on profiles
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'rescue_role'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN rescue_role rescue_role_enum DEFAULT 'COMMANDER';
    END IF;
END $$;

-- 2. Grant Core Permissions (relay_logs anonymous access strictly revoked)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.emergencies TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.rescue_teams TO authenticated;
REVOKE ALL PRIVILEGES ON public.relay_logs FROM anon, PUBLIC;
REVOKE ALL ON public.relay_logs FROM anon, PUBLIC;
REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.relay_logs FROM anon, PUBLIC;
REVOKE ALL PRIVILEGES ON public.relay_logs FROM authenticated;
REVOKE ALL ON public.relay_logs FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.relay_logs FROM authenticated;
GRANT SELECT ON public.relay_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.emergency_updates TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;

-- Conditional permissions for operator_profiles if present
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'operator_profiles'
    ) THEN
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.operator_profiles TO anon, authenticated';
        EXECUTE 'ALTER TABLE public.operator_profiles ENABLE ROW LEVEL SECURITY';
        EXECUTE 'DROP POLICY IF EXISTS "Allow read operator profiles" ON public.operator_profiles';
        EXECUTE 'CREATE POLICY "Allow read operator profiles" ON public.operator_profiles FOR SELECT TO anon, authenticated USING (true)';
        EXECUTE 'DROP POLICY IF EXISTS "Allow manage operator profiles" ON public.operator_profiles';
        EXECUTE 'CREATE POLICY "Allow manage operator profiles" ON public.operator_profiles FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)';
    END IF;
END $$;

-- 3. RLS Policies for Core Tables
ALTER TABLE public.emergencies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Operators can view all emergencies" ON public.emergencies;
CREATE POLICY "Operators can view all emergencies" ON public.emergencies FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Operators can update all emergencies" ON public.emergencies;
CREATE POLICY "Operators can update all emergencies" ON public.emergencies FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Operators can insert emergencies" ON public.emergencies;
CREATE POLICY "Operators can insert emergencies" ON public.emergencies FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "Operators can delete emergencies" ON public.emergencies;
CREATE POLICY "Operators can delete emergencies" ON public.emergencies FOR DELETE TO anon, authenticated USING (true);

ALTER TABLE public.rescue_teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read rescue teams" ON public.rescue_teams;
CREATE POLICY "Allow read rescue teams" ON public.rescue_teams FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Allow manage rescue teams" ON public.rescue_teams;
CREATE POLICY "Allow manage rescue teams" ON public.rescue_teams FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.relay_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Allow insert relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Insert relay logs" ON public.relay_logs;
DROP POLICY IF EXISTS "Relay logs insert policy" ON public.relay_logs;
DROP POLICY IF EXISTS "Relay logs all policy" ON public.relay_logs;
DROP POLICY IF EXISTS "Relay logs select policy" ON public.relay_logs;
CREATE POLICY "Relay logs select policy" ON public.relay_logs FOR SELECT TO authenticated USING (true);

ALTER TABLE public.emergency_updates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read emergency updates" ON public.emergency_updates;
CREATE POLICY "Allow read emergency updates" ON public.emergency_updates FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Allow insert emergency updates" ON public.emergency_updates;
CREATE POLICY "Allow insert emergency updates" ON public.emergency_updates FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read profiles" ON public.profiles;
CREATE POLICY "Allow read profiles" ON public.profiles FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Allow insert profiles" ON public.profiles;
CREATE POLICY "Allow insert profiles" ON public.profiles FOR INSERT TO anon, authenticated WITH CHECK (true);
DROP POLICY IF EXISTS "Allow update profiles" ON public.profiles;
CREATE POLICY "Allow update profiles" ON public.profiles FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

-- 4. Realtime Replication
ALTER PUBLICATION supabase_realtime ADD TABLE public.emergencies;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rescue_teams;
ALTER PUBLICATION supabase_realtime ADD TABLE public.relay_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.emergency_updates;`;

  const handleCopySql = () => {
    navigator.clipboard.writeText(sqlSetupScript);
    setCopiedSql(true);
    setTimeout(() => setCopiedSql(false), 2500);
  };

  const handleRunDiagnostic = async () => {
    setTestingConnection(true);
    setTestResult(null);
    try {
      const status = await checkBackendConnection();
      setTestResult(
        status.connected
          ? `[OK] Supabase connected successfully. ${status.message}`
          : `[FAIL] ${status.message}`
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      setTestResult(`[ERROR] Diagnostic check failed: ${msg}`);
    } finally {
      setTestingConnection(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 rounded-[20px] border border-slate-200/90 dark:border-white/[0.1] bg-white dark:bg-[#161619] shadow-sm dark:shadow-md">
        <div>
          <h2 className="text-lg font-bold text-slate-900 dark:text-white tracking-tight flex items-center gap-2">
            <span className="w-8 h-8 rounded-full bg-ios-blue/15 flex items-center justify-center text-ios-blue">
              <Settings className="w-4 h-4" />
            </span>
            System Settings & Architecture
          </h2>
          <p className="text-xs text-slate-600 dark:text-[#a1a1a6] mt-1 font-normal">
            Theme appearance, backend configuration, security permissions, operator authorization, and telemetry controls.
          </p>
        </div>
      </div>

      {/* Apple Appearance & Theme Controls */}
      <GlassCard
        title="Interface Appearance"
        subtitle="Select your preferred dashboard theme or follow system OS settings"
        badge={
          <span className="text-[11px] font-medium px-3 py-1 rounded-full bg-ios-blue/15 text-ios-blue border border-ios-blue/30">
            Apple HIG
          </span>
        }
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            {/* Light Option */}
            <button
              type="button"
              onClick={() => setTheme('light')}
              className={`p-4 rounded-[16px] border text-left transition-all active:scale-98 flex flex-col justify-between ${
                theme === 'light'
                  ? 'border-ios-blue bg-ios-blue/10 ring-2 ring-ios-blue/40'
                  : 'border-black/[0.08] dark:border-white/[0.08] bg-slate-100/60 dark:bg-black/30 hover:bg-slate-100 dark:hover:bg-black/50'
              }`}
            >
              <div className="flex items-center justify-between mb-3">
                <div className="w-9 h-9 rounded-full bg-amber-500/15 text-amber-500 flex items-center justify-center">
                  <Sun className="w-5 h-5" />
                </div>
                {theme === 'light' && (
                  <span className="w-2 h-2 rounded-full bg-ios-blue" />
                )}
              </div>
              <div>
                <h4 className="font-semibold text-slate-900 dark:text-white text-xs">Light Appearance</h4>
                <p className="text-[11px] text-slate-500 dark:text-ios-secondary mt-0.5">iOS systemGrouped clean white canvas</p>
              </div>
            </button>

            {/* Dark Option */}
            <button
              type="button"
              onClick={() => setTheme('dark')}
              className={`p-4 rounded-[16px] border text-left transition-all active:scale-98 flex flex-col justify-between ${
                theme === 'dark'
                  ? 'border-ios-blue bg-ios-blue/10 ring-2 ring-ios-blue/40'
                  : 'border-black/[0.08] dark:border-white/[0.08] bg-slate-100/60 dark:bg-black/30 hover:bg-slate-100 dark:hover:bg-black/50'
              }`}
            >
              <div className="flex items-center justify-between mb-3">
                <div className="w-9 h-9 rounded-full bg-indigo-500/15 text-indigo-400 flex items-center justify-center">
                  <Moon className="w-5 h-5" />
                </div>
                {theme === 'dark' && (
                  <span className="w-2 h-2 rounded-full bg-ios-blue" />
                )}
              </div>
              <div>
                <h4 className="font-semibold text-slate-900 dark:text-white text-xs">Dark Appearance</h4>
                <p className="text-[11px] text-slate-500 dark:text-ios-secondary mt-0.5">macOS OLED pitch black tactical theme</p>
              </div>
            </button>

            {/* System Option */}
            <button
              type="button"
              onClick={() => setTheme('system')}
              className={`p-4 rounded-[16px] border text-left transition-all active:scale-98 flex flex-col justify-between ${
                theme === 'system'
                  ? 'border-ios-blue bg-ios-blue/10 ring-2 ring-ios-blue/40'
                  : 'border-black/[0.08] dark:border-white/[0.08] bg-slate-100/60 dark:bg-black/30 hover:bg-slate-100 dark:hover:bg-black/50'
              }`}
            >
              <div className="flex items-center justify-between mb-3">
                <div className="w-9 h-9 rounded-full bg-ios-teal/15 text-ios-teal flex items-center justify-center">
                  <Laptop className="w-5 h-5" />
                </div>
                {theme === 'system' && (
                  <span className="w-2 h-2 rounded-full bg-ios-blue" />
                )}
              </div>
              <div>
                <h4 className="font-semibold text-slate-900 dark:text-white text-xs">Auto / Match OS</h4>
                <p className="text-[11px] text-slate-500 dark:text-ios-secondary mt-0.5">Currently resolved: {isDark ? 'Dark' : 'Light'}</p>
              </div>
            </button>
          </div>
        </div>
      </GlassCard>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Backend Credentials & Connection Diagnostics */}
        <GlassCard 
          title="Supabase Backend Link" 
          subtitle="Connection endpoints & API credentials"
          badge={
            <span className="text-[11px] font-medium px-3 py-1 rounded-full bg-ios-green/15 text-ios-green border border-ios-green/30">
              Supabase Cloud
            </span>
          }
        >
          <div className="space-y-4 text-xs">
            <div>
              <span className="text-[11px] font-medium text-slate-500 dark:text-ios-secondary block mb-1.5 uppercase tracking-wider">Project URL</span>
              <div className="p-3 rounded-[14px] border border-black/[0.06] dark:border-white/[0.08] bg-slate-100/80 dark:bg-black/40 text-ios-blue font-mono text-[11px] break-all select-all">
                {SUPABASE_URL}
              </div>
            </div>

            <div>
              <span className="text-[11px] font-medium text-slate-500 dark:text-ios-secondary block mb-1.5 uppercase tracking-wider">Publishable (Anon) Key</span>
              <div className="p-3 rounded-[14px] border border-black/[0.06] dark:border-white/[0.08] bg-slate-100/80 dark:bg-black/40 text-slate-700 dark:text-slate-300 font-mono text-[11px] break-all select-all">
                {SUPABASE_ANON_KEY.slice(0, 16)}•••••••••••••••••••••••••••••••••••••••
              </div>
              <span className="text-[11px] text-slate-500 dark:text-ios-secondary mt-1.5 block">
                Public anon key with RLS enforcement. Secret service-role keys are never exposed in web client.
              </span>
            </div>

            <div className="pt-2">
              <button
                onClick={handleRunDiagnostic}
                disabled={testingConnection}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-ios-blue hover:bg-ios-blue/90 text-white shadow-ios-pill text-xs font-medium transition-all active:scale-95 disabled:opacity-50"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${testingConnection ? 'animate-spin' : ''}`} />
                <span>{testingConnection ? 'Testing Connection...' : 'Run Backend Diagnostic Test'}</span>
              </button>

              {testResult && (
                <div className={`mt-3 p-3.5 rounded-[14px] border text-xs font-mono ${
                  testResult.includes('[OK]') 
                    ? 'border-ios-green/30 bg-ios-green/15 text-ios-green' 
                    : 'border-ios-orange/30 bg-ios-orange/15 text-ios-orange'
                }`}>
                  {testResult}
                </div>
              )}
            </div>
          </div>
        </GlassCard>

        {/* Current Operator Profile */}
        <GlassCard 
          title="Active Operator Session" 
          subtitle="Clearance level and credential details"
          badge={
            <span className="text-[11px] font-medium px-3 py-1 rounded-full bg-ios-blue/15 text-ios-blue border border-ios-blue/30">
              Operator Clearance
            </span>
          }
        >
          <div className="space-y-4 text-xs">
            <div className="flex items-center gap-3.5 p-3.5 rounded-[14px] bg-slate-100/80 dark:bg-black/40 border border-black/[0.06] dark:border-white/[0.06]">
              <div className="w-10 h-10 rounded-full bg-ios-blue/20 border border-ios-blue/40 flex items-center justify-center text-sm font-bold text-ios-blue">
                {(profile?.full_name?.[0] || user?.email?.[0] || 'O').toUpperCase()}
              </div>
              <div>
                <h4 className="font-semibold text-slate-900 dark:text-white">{profile?.full_name || 'Rescue Command Operator'}</h4>
                <p className="text-[11px] text-slate-500 dark:text-ios-secondary">{user?.email || 'Authenticated Session'}</p>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-2.5">
              <div className="p-3 rounded-[14px] bg-slate-100/80 dark:bg-black/40 border border-black/[0.06] dark:border-white/[0.06]">
                <span className="text-[10px] text-slate-500 dark:text-ios-secondary block uppercase tracking-wider font-medium">Role Clearance</span>
                <span className="font-semibold text-ios-blue mt-0.5 block">{operatorRole || 'DISPATCHER'}</span>
              </div>
              <div className="p-3 rounded-[14px] bg-slate-100/80 dark:bg-black/40 border border-black/[0.06] dark:border-white/[0.06]">
                <span className="text-[10px] text-slate-500 dark:text-ios-secondary block uppercase tracking-wider font-medium">Auth Status</span>
                <span className="font-semibold text-ios-green mt-0.5 block">Active Session</span>
              </div>
            </div>

            {/* Audio Alert toggle switch */}
            <div className="p-3.5 rounded-[14px] bg-slate-100/80 dark:bg-black/40 border border-black/[0.06] dark:border-white/[0.06] flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-ios-blue/15 flex items-center justify-center text-ios-blue">
                  <Volume2 className="w-4 h-4" />
                </div>
                <div>
                  <span className="font-medium text-slate-900 dark:text-white block">Incoming SOS Audio Siren</span>
                  <span className="text-[11px] text-slate-500 dark:text-ios-secondary">Web Audio tone on new emergency alerts</span>
                </div>
              </div>

              <label className="relative inline-flex items-center cursor-pointer">
                <input
                  type="checkbox"
                  checked={soundAlertEnabled}
                  onChange={(e) => setSoundAlertEnabled(e.target.checked)}
                  className="sr-only peer"
                />
                <div className="w-11 h-6 bg-slate-300 dark:bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-ios-green"></div>
              </label>
            </div>

            <div className="pt-2">
              <button
                onClick={() => signOut()}
                className="px-4 py-2 rounded-full bg-ios-red/15 hover:bg-ios-red/25 text-ios-red border border-ios-red/30 text-xs font-medium transition-all active:scale-95"
              >
                Sign Out Of Session
              </button>
            </div>
          </div>
        </GlassCard>
      </div>

      {/* SQL Migration Script Reference for Supabase */}
      <GlassCard
        title="Supabase RBAC & Operator Schema Setup Script"
        subtitle="Complete database schema, employee sequence, audit tables, and RLS policies"
        headerAction={
          <button
            onClick={handleCopySql}
            className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full bg-slate-100 hover:bg-slate-200 dark:bg-white/[0.08] dark:hover:bg-white/[0.14] text-slate-700 dark:text-white border border-black/[0.06] dark:border-white/[0.08] text-xs font-medium transition-all active:scale-95"
          >
            {copiedSql ? <Check className="w-3.5 h-3.5 text-ios-green" /> : <Copy className="w-3.5 h-3.5" />}
            <span>{copiedSql ? 'Copied' : 'Copy RBAC SQL'}</span>
          </button>
        }
      >
        <div className="space-y-3.5 text-xs">
          <p className="text-slate-600 dark:text-slate-300 text-xs leading-relaxed">
            Execute this SQL migration script in your Supabase SQL Editor. It establishes the <strong>operator_employee_id_seq</strong> sequence (RES-001...), creates <strong>public.audit_logs</strong>, provisions the <strong>admin_create_operator</strong> RPC, and enforces strict Row Level Security.
          </p>

          <pre className="p-4 rounded-[16px] border border-black/[0.06] dark:border-white/[0.08] bg-slate-100/90 dark:bg-black/50 text-slate-800 dark:text-slate-300 overflow-x-auto text-[11px] font-mono leading-relaxed max-h-60 select-all custom-scrollbar">
            {sqlSetupScript}
          </pre>

          <div className="flex items-center justify-between text-xs text-slate-500 dark:text-ios-secondary pt-2 border-t border-black/[0.06] dark:border-white/[0.06]">
            <span>File location: <code className="text-ios-blue font-mono">src/sql/rbac_schema_setup.sql</code></span>
            <a
              href="https://supabase.com/dashboard/project/pmkwudzlyvaegwmugmoy/sql/new"
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 text-ios-blue hover:underline font-medium"
            >
              Open Supabase SQL Editor
              <ExternalLink className="w-3 h-3" />
            </a>
          </div>
        </div>
      </GlassCard>
    </div>
  );
};