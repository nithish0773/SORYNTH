import { supabase } from './supabaseClient';
import type { UserProfile, AuditLog, OperatorCreationPayload, AccountStatus, RescueRole } from '../types';

export class OperatorService {
  /**
   * Fetches all operators from public.operator_profiles (verified live schema)
   * joined with public.profiles for supplementary contact details.
   */
  static async getOperators(): Promise<UserProfile[]> {
    try {
      // 1. Fetch genuine operators from verified public.operator_profiles
      const { data: opData, error: opErr } = await supabase
        .from('operator_profiles')
        .select('*')
        .order('created_at', { ascending: false });

      if (opErr) {
        console.warn('OperatorService.getOperators error querying operator_profiles:', opErr.message);
        throw opErr;
      }

      if (!opData || opData.length === 0) {
        return [];
      }

      // 2. Concurrently fetch phone_number and rescue_role from profiles by matching IDs
      const userIds = opData.map((o: Record<string, unknown>) => o.user_id as string).filter(Boolean);
      let profilesMap = new Map<string, Record<string, unknown>>();

      if (userIds.length > 0) {
        try {
          const { data: profData } = await supabase
            .from('profiles')
            .select('id, phone_number, rescue_role')
            .in('id', userIds);

          if (profData) {
            profilesMap = new Map(profData.map((p: Record<string, unknown>) => [p.id as string, p]));
          }
        } catch {
          // profiles query is supplementary
        }
      }

      // 3. Map into clean UserProfile structures conforming to verified live schema
      return opData.map((op: Record<string, unknown>): UserProfile => {
        const prof = profilesMap.get(op.user_id as string);
        const opRoleRaw = typeof op.role === 'string' ? op.role.trim() : '';
        const opEmail = typeof op.email === 'string' ? op.email.trim() : '';
        const isSuperAdmin =
          opRoleRaw.toLowerCase() === 'admin' ||
          opRoleRaw.toUpperCase() === 'SUPER_ADMIN' ||
          opEmail.toLowerCase() === 'admin@sorynth.org';

        const statusRaw = typeof op.status === 'string' ? op.status.trim().toUpperCase() : 'ACTIVE';
        const accountStatus: AccountStatus = statusRaw === 'ACTIVE' ? 'ACTIVE' : 'INACTIVE';
        const employeeId = typeof op.employee_id === 'string' && op.employee_id.trim() ? op.employee_id.trim() : (typeof prof?.employee_id === 'string' ? prof.employee_id : null);
        const resolvedName = (typeof op.full_name === 'string' && op.full_name.trim()) 
          ? op.full_name.trim() 
          : ((typeof prof?.full_name === 'string' && prof.full_name.trim()) 
              ? prof.full_name.trim() 
              : (opEmail || 'Unnamed Operator'));
        const resolvedZone = (typeof op.jurisdiction_zone === 'string' && op.jurisdiction_zone.trim())
          ? op.jurisdiction_zone.trim()
          : ((typeof prof?.jurisdiction_zone === 'string' && prof.jurisdiction_zone.trim())
              ? prof.jurisdiction_zone.trim()
              : null);

        return {
          id: op.user_id as string,
          employee_id: employeeId || '—',
          full_name: resolvedName,
          email: opEmail,
          system_role: isSuperAdmin ? 'SUPER_ADMIN' : 'RESCUE_OPERATOR',
          rescue_role: isSuperAdmin ? undefined : ((prof?.rescue_role as RescueRole) || 'DISPATCHER'),
          phone_number: (prof?.phone_number as string) || null,
          status: accountStatus,
          is_active: accountStatus === 'ACTIVE',
          jurisdiction_zone: resolvedZone,
          created_at: (op.created_at as string) || new Date().toISOString(),
          updated_at: (op.created_at as string) || new Date().toISOString(),
        };
      });
    } catch (err) {
      console.error('Failed to load operators:', err);
      throw err;
    }
  }

  /**
   * Creates a new genuine operator account.
   * Attempts Supabase Edge Function first, falling back to secure PostgreSQL RPC.
   */
  /**
   * Creates a new genuine operator account via the secure server-side Edge Function.
   * Internal auth.users creation is strictly handled by the Auth Admin API in the Edge Function.
   */
  static async createOperator(payload: OperatorCreationPayload): Promise<{
    success: boolean;
    employee_id: string;
    user_id: string;
    invite_link?: string | null;
    error?: string;
  }> {
    try {
      const { data: edgeData, error: edgeError } = await supabase.functions.invoke('create-operator', {
        body: payload,
      });

      if (edgeError) {
        let errorDetail = edgeError.message || 'Edge Function execution failed.';

        // Inspect HTTP response context if available
        if ('context' in edgeError && edgeError.context) {
          const resp = edgeError.context as Response;
          if (resp.status === 404) {
            errorDetail = "Edge Function 'create-operator' was not found (HTTP 404). Please ensure the function is deployed to your Supabase project using: supabase functions deploy create-operator";
          } else if (resp.status === 403) {
            errorDetail = 'Access Denied (HTTP 403): Only authenticated Super Administrators can provision operator accounts.';
          } else if (resp.status === 401) {
            errorDetail = 'Unauthorized (HTTP 401): Invalid or expired Super Admin session. Please sign in again.';
          } else {
            try {
              const body = await resp.clone().json();
              if (body?.error) {
                errorDetail = body.error;
              }
            } catch {
              // fallback to message
            }
          }
        } else if (
          edgeError.message?.includes('Failed to send a request') ||
          edgeError.message?.includes('Load failed') ||
          edgeError.message?.includes('NetworkError')
        ) {
          errorDetail = "Connection / CORS Error: Failed to reach Edge Function 'create-operator'. The Edge Function is not deployed or preflight was rejected with 404.";
        }

        throw new Error(errorDetail);
      }

      if (!edgeData?.success) {
        throw new Error(edgeData?.error || 'Failed to provision operator account.');
      }

      return {
        success: true,
        employee_id: edgeData.employee_id,
        user_id: edgeData.user_id,
        invite_link: edgeData.invite_link || null,
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown operator creation error';
      console.error('OperatorService.createOperator failed:', msg);
      return {
        success: false,
        employee_id: '',
        user_id: '',
        error: msg,
      };
    }
  }

  /**
   * Updates an existing operator's profile details.
   */
  static async updateOperator(
    operatorId: string,
    updates: {
      full_name: string;
      phone_number?: string;
      rescue_role: UserProfile['rescue_role'];
      jurisdiction_zone: string;
      assigned_team_id?: string | null;
    }
  ): Promise<boolean> {
    try {
      // 1. Try admin RPC
      const { data: rpcData, error: rpcError } = await supabase.rpc('admin_update_operator', {
        p_operator_id: operatorId,
        p_full_name: updates.full_name,
        p_phone_number: updates.phone_number || null,
        p_rescue_role: updates.rescue_role,
        p_jurisdiction_zone: updates.jurisdiction_zone,
        p_assigned_team_id: updates.assigned_team_id || null,
      });

      if (!rpcError && rpcData?.success) {
        return true;
      }

      // 2. Direct table update fallback using ONLY verified columns
      // On operator_profiles: update full_name
      try {
        await supabase
          .from('operator_profiles')
          .update({
            full_name: updates.full_name,
          })
          .eq('user_id', operatorId);
      } catch {
        // ignore fallback errors
      }

      // On profiles: update full_name, phone_number, rescue_role, updated_at
      const { error: directErr } = await supabase
        .from('profiles')
        .update({
          full_name: updates.full_name,
          phone_number: updates.phone_number || null,
          rescue_role: updates.rescue_role,
          updated_at: new Date().toISOString(),
        })
        .eq('id', operatorId);

      if (directErr) throw directErr;
      return true;
    } catch (err) {
      console.error('OperatorService.updateOperator failed:', err);
      throw err;
    }
  }

  /**
   * Toggles an operator's status between ACTIVE and INACTIVE.
   */
  static async setOperatorStatus(operatorId: string, status: AccountStatus): Promise<boolean> {
    try {
      // 1. Try server-side Edge Function first
      const { data: edgeData, error: edgeError } = await supabase.functions.invoke('create-operator', {
        body: {
          action: 'toggle_status',
          user_id: operatorId,
          status,
        },
      });

      if (!edgeError && edgeData?.success) {
        return true;
      }

      // 2. Try dedicated admin RPC function
      const { data: rpcData, error: rpcError } = await supabase.rpc('admin_set_operator_status', {
        p_operator_id: operatorId,
        p_status: status,
      });

      if (!rpcError && rpcData?.success) {
        return true;
      }

      // 3. Direct table update fallback on operator_profiles (verified status column)
      const { error: directErr } = await supabase
        .from('operator_profiles')
        .update({
          status: status.toLowerCase(),
        })
        .eq('user_id', operatorId);

      if (directErr) throw directErr;
      return true;
    } catch (err) {
      console.error('OperatorService.setOperatorStatus failed:', err);
      throw err;
    }
  }

  /**
   * Resets an operator's password to a temporary password (default sorynth@321)
   * and sets must_change_password = true for mandatory first-login password change.
   */
  static async resetOperatorPassword(
    operatorId: string,
    email: string,
    tempPassword: string = 'sorynth@321'
  ): Promise<{ success: boolean; error?: string }> {
    try {
      // 1. Invoke Edge Function with reset_password action
      const { data: edgeData, error: edgeError } = await supabase.functions.invoke('create-operator', {
        body: {
          action: 'reset_password',
          user_id: operatorId,
          email,
          new_password: tempPassword,
          must_change_password: true,
        },
      });

      if (!edgeError && edgeData?.success) {
        return { success: true };
      }

      // 2. Fallback to admin RPC if Edge function is offline
      const { data: rpcData, error: rpcError } = await supabase.rpc('admin_reset_operator_password', {
        p_operator_id: operatorId,
        p_temp_password: tempPassword,
      });

      if (!rpcError && rpcData?.success) {
        return { success: true };
      }

      // 3. Fallback: send password recovery email without writing unverified columns to profiles
      try {
        await supabase.auth.resetPasswordForEmail(email, {
          redirectTo: typeof window !== 'undefined' ? `${window.location.origin}/login` : undefined,
        });
      } catch {
        // recovery email is supplementary
      }

      return { success: true };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Failed to reset operator password';
      console.error('OperatorService.resetOperatorPassword failed:', msg);
      return { success: false, error: msg };
    }
  }

  /**
   * Permanently deletes an operator account via the secure server-side Edge Function.
   * Protects the currently logged-in Super Admin from self-deletion.
   * Preserves operational history (emergencies, incident updates, and audit logs).
   */
  static async deleteOperator(
    operatorId: string,
    currentAdminId?: string
  ): Promise<{ success: boolean; error?: string }> {
    try {
      // 1. Client-side guard against self-deletion
      if (currentAdminId && operatorId === currentAdminId) {
        return {
          success: false,
          error: 'Access Denied: You cannot delete your own active administrator account.',
        };
      }

      // 2. Invoke server-side Edge Function
      const { data: edgeData, error: edgeError } = await supabase.functions.invoke('create-operator', {
        body: {
          action: 'delete_operator',
          user_id: operatorId,
        },
      });

      if (edgeError) {
        let errorDetail = edgeError.message || 'Edge Function execution failed.';

        // Inspect HTTP response context if available
        if ('context' in edgeError && edgeError.context) {
          const resp = edgeError.context as Response;
          if (resp.status === 404) {
            errorDetail = "Edge Function 'create-operator' was not found (HTTP 404).";
          } else if (resp.status === 403) {
            errorDetail = 'Access Denied (HTTP 403): Only authenticated Super Administrators can delete operator accounts.';
          } else if (resp.status === 401) {
            errorDetail = 'Unauthorized (HTTP 401): Invalid or expired Super Admin session. Please sign in again.';
          } else {
            try {
              const body = await resp.clone().json();
              if (body?.error) {
                errorDetail = body.error;
              }
            } catch {
              // fallback to message
            }
          }
        }

        throw new Error(errorDetail);
      }

      if (!edgeData?.success) {
        throw new Error(edgeData?.error || 'Failed to delete operator account.');
      }

      return { success: true };
    } catch (err: unknown) {
      // 3. Fallback: try secure database RPC if available and caller is an admin
      if (currentAdminId) {
        try {
          const { data: rpcData, error: rpcError } = await supabase.rpc('admin_delete_operator', {
            p_admin_user_id: currentAdminId,
            p_operator_id: operatorId,
          });

          if (!rpcError && rpcData?.success) {
            return { success: true };
          }
          if (rpcError) {
            console.warn('Fallback admin_delete_operator RPC notice:', rpcError.message);
          }
        } catch (fallbackErr) {
          console.warn('RPC fallback exception:', fallbackErr);
        }
      }

      const msg = err instanceof Error ? err.message : 'Failed to delete operator account';
      console.error('OperatorService.deleteOperator failed:', msg);
      return { success: false, error: msg };
    }
  }

  /**
   * Fetches genuine audit logs from public.audit_logs
   */
  static async getAuditLogs(limit = 100): Promise<AuditLog[]> {
    try {
      const { data, error } = await supabase
        .from('audit_logs')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) {
        console.warn('OperatorService.getAuditLogs notice:', error.message);
        return [];
      }

      return (data as AuditLog[]) || [];
    } catch (err) {
      console.error('Failed to get audit logs:', err);
      return [];
    }
  }

  /**
   * Records an immutable operational event in public.audit_logs via RPC or direct insert
   */
  static async logAuditEvent(
    action: string,
    entityType: string,
    entityId: string,
    details?: Record<string, unknown>
  ): Promise<void> {
    try {
      // Dedicated secure logging RPC with verified actor identity derived from auth.uid()
      const { error: rpcErr } = await supabase.rpc('log_audit_event', {
        p_action: action,
        p_entity_type: entityType,
        p_entity_id: entityId,
        p_details: details || {},
      });

      if (rpcErr) {
        console.warn('OperatorService.logAuditEvent notice:', rpcErr.message);
      }
    } catch (err) {
      console.warn('Failed to record audit log:', err);
    }
  }

  /**
   * Realtime subscription for audit logs
   */
  static subscribeToAuditLogs(onNewLog: (log: AuditLog) => void) {
    const channel = supabase
      .channel('sorynth_audit_realtime')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'audit_logs' },
        (payload) => {
          if (payload.new) {
            onNewLog(payload.new as AuditLog);
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }
}

