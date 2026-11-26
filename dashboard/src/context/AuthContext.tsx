import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import type { User, Session } from '@supabase/supabase-js';
import { supabase } from '../services/supabaseClient';
import type { RescueRole, SystemRole, UserProfile, AccountStatus } from '../types';

interface AuthContextType {
  user: User | null;
  session: Session | null;
  profile: UserProfile | null;
  systemRole: SystemRole | null;
  operatorRole: RescueRole | null;
  employeeId: string | null;
  isAdmin: boolean;
  isOperator: boolean;
  mustChangePassword: boolean;
  isLoading: boolean;
  error: string | null;
  signIn: (email: string, password: string) => Promise<{ success: boolean; error?: string; systemRole?: SystemRole }>;
  signOut: () => Promise<void>;
  changePassword: (newPassword: string) => Promise<{ success: boolean; error?: string }>;
  refreshProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [systemRole, setSystemRole] = useState<SystemRole | null>(null);
  const [operatorRole, setOperatorRole] = useState<RescueRole | null>(null);
  const [employeeId, setEmployeeId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const fetchUserProfile = useCallback(async (userId: string, currentUser?: User): Promise<UserProfile | null> => {
    try {
      // 1. Authoritative server-side RPC verification (is_super_admin)
      let isDbSuperAdmin = false;
      try {
        const { data: rpcAdmin, error: rpcErr } = await supabase.rpc('is_super_admin', { p_user_id: userId });
        if (!rpcErr && typeof rpcAdmin === 'boolean') {
          isDbSuperAdmin = rpcAdmin;
        }
      } catch {
        try {
          const { data: rpcNoArg, error: rpcNoArgErr } = await supabase.rpc('is_super_admin');
          if (!rpcNoArgErr && typeof rpcNoArg === 'boolean') {
            isDbSuperAdmin = rpcNoArg;
          }
        } catch {
          // RPC may be pending database migration
        }
      }

      // 2. Query public.profiles
      const { data: profileData } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();

      // 3. Query public.operator_profiles for dual-table resilience
      let opData: Record<string, unknown> | null = null;
      try {
        const { data: opProfile } = await supabase
          .from('operator_profiles')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();
        opData = (opProfile as Record<string, unknown>) || null;
      } catch {
        // Table or columns may be pending migration
      }

      const p = profileData as UserProfile | null;

      // 4. Authoritative resolution based on verified live schema
      // Live Admin: UUID b2ab7209-5bc9-4e21-91ea-d02f92ae40aa, operator_profiles.role = 'admin', employee_id = 'ADM-001'
      const opRoleRaw = typeof opData?.role === 'string' ? opData.role.trim() : '';
      const opRoleUpper = opRoleRaw.toUpperCase();
      const metaRoleUpper = (currentUser?.app_metadata?.role || currentUser?.user_metadata?.role || '').trim().toUpperCase();
      const userEmailLower = (currentUser?.email || (typeof opData?.email === 'string' ? opData.email : '') || p?.email || '').trim().toLowerCase();

      const isSuperAdmin = Boolean(
        isDbSuperAdmin ||
        userId === 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa' ||
        userEmailLower === 'admin@sorynth.org' ||
        opRoleUpper === 'SUPER_ADMIN' ||
        opRoleUpper === 'ADMIN' ||
        metaRoleUpper === 'SUPER_ADMIN'
      );

      // 5. Account Clearance & Missing Operator Account Handling
      if (!isSuperAdmin) {
        // Defense-in-depth: If no operator_profiles record exists, user has no rescue clearance
        if (!opData) {
          console.warn('Access denied: No operator clearance found in operator_profiles for user:', userId, userEmailLower);
          await supabase.auth.signOut();
          setUser(null);
          setSession(null);
          setProfile(null);
          setSystemRole(null);
          setOperatorRole(null);
          setEmployeeId(null);
          setError('Access Denied: No rescue operator or administrator profile is assigned to this account.');
          return null;
        }

        // Suspended / Deactivated operator check (case-insensitive)
        const opStatusUpper = String(opData.status || '').trim().toUpperCase();
        if (opStatusUpper === 'INACTIVE' || opStatusUpper === 'SUSPENDED') {
          console.warn('Operator account suspended/deactivated:', userEmailLower);
          await supabase.auth.signOut();
          setUser(null);
          setSession(null);
          setProfile(null);
          setSystemRole(null);
          setOperatorRole(null);
          setEmployeeId(null);
          setError('This operator account has been suspended. Please contact your Super Administrator.');
          return null;
        }
      }

      const trustedRole: SystemRole = isSuperAdmin ? 'SUPER_ADMIN' : 'RESCUE_OPERATOR';

      // 6. Set employee ID and role badges
      // For Super Admin, strictly enforce ADM-001 (stripping any accidental operator RES- prefix)
      const opEmployeeId = typeof opData?.employee_id === 'string' ? opData.employee_id : null;
      const candidateId = opEmployeeId;
      const resolvedEmployeeId = isSuperAdmin
        ? (candidateId && candidateId.startsWith('ADM-') ? candidateId : 'ADM-001')
        : (candidateId || null);
      setEmployeeId(resolvedEmployeeId);

      // Super Admin has NO field operator role (null), preventing dispatcher/operator badges
      if (trustedRole === 'SUPER_ADMIN') {
        setOperatorRole(null);
      } else {
        setOperatorRole((p?.rescue_role as RescueRole) || 'DISPATCHER');
      }

      setSystemRole(trustedRole);

      // 7. Compose unified profile from verified columns:
      // operator_profiles: user_id, employee_id, full_name, email, role, status, created_at
      // profiles: id, full_name, phone_number, email, rescue_role, created_at, updated_at
      const opFullName = typeof opData?.full_name === 'string' ? opData.full_name : null;
      const opEmail = typeof opData?.email === 'string' ? opData.email : null;
      const rawStatus = typeof opData?.status === 'string' ? opData.status.toUpperCase() : 'ACTIVE';
      const opStatus: AccountStatus = rawStatus === 'ACTIVE' ? 'ACTIVE' : 'INACTIVE';
      const opCreatedAt = typeof opData?.created_at === 'string' ? opData.created_at : undefined;

      const resolvedProfile: UserProfile = {
        id: userId,
        full_name: opFullName || p?.full_name || currentUser?.user_metadata?.full_name || currentUser?.email?.split('@')[0] || '—',
        email: opEmail || p?.email || currentUser?.email || '',
        system_role: trustedRole,
        rescue_role: trustedRole === 'SUPER_ADMIN' ? undefined : (p?.rescue_role || 'DISPATCHER'),
        employee_id: resolvedEmployeeId,
        status: opStatus,
        is_active: opStatus === 'ACTIVE',
        must_change_password: Boolean(currentUser?.user_metadata?.must_change_password),
        jurisdiction_zone: (typeof opData?.jurisdiction_zone === 'string' ? opData.jurisdiction_zone : null) || (p?.jurisdiction_zone as string) || (currentUser?.user_metadata?.jurisdiction_zone as string) || null,
        phone_number: p?.phone_number || null,
        created_at: opCreatedAt || p?.created_at || new Date().toISOString(),
        updated_at: p?.updated_at || new Date().toISOString(),
      };

      setProfile(resolvedProfile);
      return resolvedProfile;
    } catch (err) {
      console.warn('Profile fetch warning:', err);
      return null;
    }
  }, []);

  useEffect(() => {
    // 1. Check initial active Supabase session
    supabase.auth.getSession().then(({ data: { session: initSession } }) => {
      setSession(initSession);
      setUser(initSession?.user ?? null);
      if (initSession?.user) {
        fetchUserProfile(initSession.user.id, initSession.user).finally(() => setIsLoading(false));
      } else {
        setIsLoading(false);
      }
    });

    // 2. Listen to genuine auth state transitions
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (_event, newSession) => {
      setSession(newSession);
      if (newSession?.user) {
        setUser(newSession.user);
        await fetchUserProfile(newSession.user.id, newSession.user);
      } else {
        setUser(null);
        setProfile(null);
        setSystemRole(null);
        setOperatorRole(null);
        setEmployeeId(null);
      }
      setIsLoading(false);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [fetchUserProfile]);

  const signIn = async (email: string, password: string) => {
    setError(null);
    setIsLoading(true);
    try {
      const cleanEmail = email.trim().toLowerCase();
      const { data, error: signInErr } = await supabase.auth.signInWithPassword({
        email: cleanEmail,
        password,
      });

      if (signInErr) {
        setError(signInErr.message);
        setIsLoading(false);
        return { success: false, error: signInErr.message };
      }

      if (!data.user) {
        setIsLoading(false);
        return { success: false, error: 'User session not created.' };
      }

      setUser(data.user);
      setSession(data.session);

      // Verify profile and account status
      const userProf = await fetchUserProfile(data.user.id, data.user);
      if (!userProf) {
        setIsLoading(false);
        return { success: false, error: 'Account deactivated or profile unavailable.' };
      }

      const activeRole = userProf.system_role;

      // Log successful login audit event
      try {
        await supabase.from('audit_logs').insert({
          actor_id: data.user.id,
          actor_email: data.user.email,
          actor_name: userProf.full_name,
          actor_role: activeRole,
          action: 'LOGIN',
          entity_type: 'AUTH',
          entity_id: userProf.employee_id || data.user.id,
          details: { login_timestamp: new Date().toISOString() },
        });
      } catch {
        // audit table may be pending creation
      }

      setIsLoading(false);
      return { success: true, systemRole: activeRole };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Login failed';
      setError(msg);
      setIsLoading(false);
      return { success: false, error: msg };
    }
  };

  const signOut = async () => {
    try {
      if (user) {
        try {
          await supabase.from('audit_logs').insert({
            actor_id: user.id,
            actor_email: user.email,
            actor_name: profile?.full_name || user.email,
            actor_role: systemRole || 'RESCUE_OPERATOR',
            action: 'LOGOUT',
            entity_type: 'AUTH',
            entity_id: employeeId || user.id,
            details: { logout_timestamp: new Date().toISOString() },
          });
        } catch {
          // ignore
        }
      }

      await supabase.auth.signOut();
      setUser(null);
      setSession(null);
      setProfile(null);
      setSystemRole(null);
      setOperatorRole(null);
      setEmployeeId(null);
      setError(null);
    } catch (err) {
      console.error('Sign out error:', err);
    }
  };

  const changePassword = async (newPassword: string): Promise<{ success: boolean; error?: string }> => {
    try {
      if (!newPassword || newPassword.length < 8) {
        return { success: false, error: 'Password must be at least 8 characters in length.' };
      }

      // Update auth user password and clear must_change_password metadata
      const { error: updErr } = await supabase.auth.updateUser({
        password: newPassword,
        data: {
          must_change_password: false,
        },
      });

      if (updErr) {
        return { success: false, error: updErr.message };
      }

      // Refresh cached user profile with updated user_metadata
      if (user) {
        await fetchUserProfile(user.id, {
          ...user,
          user_metadata: { ...user.user_metadata, must_change_password: false },
        });
      }

      // Log password update audit event
      if (user) {
        try {
          await supabase.from('audit_logs').insert({
            actor_id: user.id,
            actor_email: user.email,
            actor_name: profile?.full_name || user.email,
            actor_role: systemRole || 'RESCUE_OPERATOR',
            action: 'PASSWORD_CHANGED',
            entity_type: 'PASSWORD',
            entity_id: employeeId || user.id,
            details: { updated_at: new Date().toISOString() },
          });
        } catch {
          // ignore
        }
      }

      return { success: true };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to update password';
      return { success: false, error: msg };
    }
  };

  const refreshProfile = async () => {
    if (user) {
      await fetchUserProfile(user.id, user);
    }
  };

  const isAdmin = systemRole === 'SUPER_ADMIN';
  const isOperator = systemRole === 'RESCUE_OPERATOR';
  const mustChangePassword = Boolean(profile?.must_change_password || user?.user_metadata?.must_change_password);

  return (
    <AuthContext.Provider
      value={{
        user,
        session,
        profile,
        systemRole,
        operatorRole,
        employeeId,
        isAdmin,
        isOperator,
        mustChangePassword,
        isLoading,
        error,
        signIn,
        signOut,
        changePassword,
        refreshProfile,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
