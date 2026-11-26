import { createClient } from '@supabase/supabase-js';

// Fallback configuration if .env is missing or loading
const DEFAULT_SUPABASE_URL = 'https://pmkwudzlyvaegwmugmoy.supabase.co';
const DEFAULT_SUPABASE_ANON_KEY = 'sb_publishable_g9JmugniAZgkgz4LSKgRHg_cEsJsnpD';

export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || DEFAULT_SUPABASE_URL;
export const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY;

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    storage: typeof window !== 'undefined' ? window.localStorage : undefined,
  },
  realtime: {
    params: {
      eventsPerSecond: 10,
    },
  },
});

export interface ConnectionStatus {
  connected: boolean;
  message: string;
  hasOperatorAccess: boolean;
  timestamp: string;
}

/**
 * Tests connection to Supabase and assesses table read permissions
 */
export async function checkBackendConnection(): Promise<ConnectionStatus> {
  try {
    // 1. Verify general REST connectivity via RPC
    const { error: rpcError } = await supabase.rpc('get_emergency_status', {
      p_emergency_code: 'PING_CHECK',
    });

    if (rpcError && rpcError.code === 'PGRST301') {
      return {
        connected: false,
        message: 'Invalid Supabase API credentials or project unreachable.',
        hasOperatorAccess: false,
        timestamp: new Date().toISOString(),
      };
    }

    // 2. Check if current user has SELECT access on emergencies
    const { error: selectError } = await supabase
      .from('emergencies')
      .select('id')
      .limit(1);

    const hasOperatorAccess = !selectError;

    return {
      connected: true,
      message: hasOperatorAccess 
        ? 'Connected with Operator Privileges' 
        : 'Connected to Supabase. RLS policy active - login as operator required for full table scan.',
      hasOperatorAccess,
      timestamp: new Date().toISOString(),
    };
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Network error';
    return {
      connected: false,
      message: `Failed to reach Supabase backend: ${errorMsg}`,
      hasOperatorAccess: false,
      timestamp: new Date().toISOString(),
    };
  }
}
