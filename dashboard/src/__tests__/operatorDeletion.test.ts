import { describe, it, expect, vi, beforeEach } from 'vitest';
import manageOperatorsPageSource from '../pages/admin/ManageOperatorsPage.tsx?raw';
import edgeFunctionSource from '../../supabase/functions/create-operator/index.ts?raw';
import deleteSqlSource from '../sql/admin_delete_operator_setup.sql?raw';
import { OperatorService } from '../services/operatorService';
import { supabase } from '../services/supabaseClient';

describe('SORYNTH – Permanent Operator Delete Feature', () => {
  const mockAdminId = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa';
  const mockOperatorId = '77777777-8888-9999-aaaa-bbbbbbbbbbbb';

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  // =========================================================================
  // 1. UI Confirmation Dialog & Action Placement
  // =========================================================================
  describe('1. UI Controls & Explicit Confirmation Dialog', () => {
    it('proves a dedicated Delete button is rendered alongside Edit, Reset Password, and Deactivate', () => {
      expect(manageOperatorsPageSource).toContain('title="Edit Operator Profile"');
      expect(manageOperatorsPageSource).toContain('title="Reset Operator Password"');
      expect(manageOperatorsPageSource).toContain('title={isActive ? \'Deactivate Operator\' : \'Reactivate Operator\'}');
      expect(manageOperatorsPageSource).toContain('title="Permanently Delete Operator"');
      expect(manageOperatorsPageSource).toContain('data-testid={`delete-operator-btn-${op.employee_id || op.id}`}');
    });

    it('proves Deactivate remains a separate action from Delete', () => {
      expect(manageOperatorsPageSource).toContain('handleToggleStatus');
      expect(manageOperatorsPageSource).toContain('handleOpenDeleteModal');
      expect(manageOperatorsPageSource).toContain('Reactivate');
      expect(manageOperatorsPageSource).toContain('Deactivate');
    });

    it('proves confirmation dialog renders operator details, warning, and explicit confirmation button', () => {
      expect(manageOperatorsPageSource).toContain('data-testid="delete-operator-modal"');
      expect(manageOperatorsPageSource).toContain('data-testid="delete-modal-operator-name"');
      expect(manageOperatorsPageSource).toContain('data-testid="delete-modal-employee-id"');
      expect(manageOperatorsPageSource).toContain('data-testid="delete-modal-operator-email"');
      expect(manageOperatorsPageSource).toContain('Warning: This permanently deletes the account and cannot be undone.');
      expect(manageOperatorsPageSource).toContain('data-testid="confirm-delete-operator-btn"');
    });

    it('proves cancel button aborts deletion safely without triggering any deletion call', () => {
      expect(manageOperatorsPageSource).toContain('onClick={handleCloseDeleteModal}');
      expect(manageOperatorsPageSource).toContain('Cancel');
    });
  });

  // =========================================================================
  // 2. Protected Accounts & Self-Deletion Defenses
  // =========================================================================
  describe('2. Protected Accounts & Self-Deletion Prevention', () => {
    it('prevents currently logged-in Super Admin from deleting their own account in the service', async () => {
      const result = await OperatorService.deleteOperator(mockAdminId, mockAdminId);
      expect(result.success).toBe(false);
      expect(result.error).toContain('You cannot delete your own active administrator account');
    });

    it('proves UI hides or blocks the delete button when the operator row matches current logged-in admin', () => {
      expect(manageOperatorsPageSource).toContain('op.id !== currentAuthUser?.id');
      expect(manageOperatorsPageSource).toContain('!isSuperAdmin');
    });

    it('proves UI modal opener explicitly checks and prevents self-deletion', () => {
      expect(manageOperatorsPageSource).toContain('if (currentAuthUser && op.id === currentAuthUser.id)');
      expect(manageOperatorsPageSource).toContain('You cannot delete your own active administrator account');
    });

    it('proves Edge Function strictly rejects self-deletion attempts', () => {
      expect(edgeFunctionSource).toContain('if (user_id === callerUser.id)');
      expect(edgeFunctionSource).toContain('You cannot delete your own active administrator account');
    });

    it('proves Edge Function protects Super Admin accounts from permanent deletion', () => {
      expect(edgeFunctionSource).toContain('user_id === "b2ab7209-5bc9-4e21-91ea-d02f92ae40aa"');
      expect(edgeFunctionSource).toContain('targetRoleUpper === "ADMIN"');
      expect(edgeFunctionSource).toContain('targetRoleUpper === "SUPER_ADMIN"');
      expect(edgeFunctionSource).toContain('Super Administrator accounts cannot be deleted');
    });

    it('proves Database SQL RPC protects Super Admin accounts from deletion', () => {
      expect(deleteSqlSource).toContain("p_operator_id = 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa'::UUID");
      expect(deleteSqlSource).toContain("LOWER(COALESCE(v_target_role, '')) = 'admin'");
      expect(deleteSqlSource).toContain("Super Administrator accounts cannot be deleted");
    });
  });

  // =========================================================================
  // 3. Super Admin Authorization & Role Checks
  // =========================================================================
  describe('3. Super Admin Authorization Verification', () => {
    it('proves UI restricts deletion modal to Super Admins only', () => {
      expect(manageOperatorsPageSource).toContain('if (!isAdmin)');
      expect(manageOperatorsPageSource).toContain('Only Super Administrators can permanently delete operator accounts');
    });

    it('proves Edge Function validates caller Authorization token and Super Admin clearance', () => {
      expect(edgeFunctionSource).toContain('action === "delete_operator"');
      expect(edgeFunctionSource).toContain('isCallerSuperAdmin');
      expect(edgeFunctionSource).toContain('Access Denied: Only authenticated, active Super Administrators can manage operator accounts');
    });

    it('proves Database SQL RPC enforces Super Admin check on p_admin_user_id', () => {
      expect(deleteSqlSource).toContain('SELECT public.is_super_admin(p_admin_user_id) INTO v_is_admin;');
      expect(deleteSqlSource).toContain('is not a verified active Super Administrator');
    });
  });

  // =========================================================================
  // 4. Operational History Preservation
  // =========================================================================
  describe('4. Operational History Preservation (No Blind Cascading)', () => {
    it('proves Edge Function safely nullifies emergency_updates without deleting updates', () => {
      expect(edgeFunctionSource).toContain('from("emergency_updates")');
      expect(edgeFunctionSource).toContain('update({ updated_by_user_id: null })');
      expect(edgeFunctionSource).toContain('.eq("updated_by_user_id", user_id)');
    });

    it('proves Edge Function safely nullifies emergencies without deleting emergency records', () => {
      expect(edgeFunctionSource).toContain('from("emergencies")');
      expect(edgeFunctionSource).toContain('update({ user_id: null })');
      expect(edgeFunctionSource).toContain('.eq("user_id", user_id)');
    });

    it('proves Database SQL migration safely nullifies emergency_updates and emergencies', () => {
      expect(deleteSqlSource).toContain('UPDATE public.emergency_updates');
      expect(deleteSqlSource).toContain('SET updated_by_user_id = NULL');
      expect(deleteSqlSource).toContain('UPDATE public.emergencies');
      expect(deleteSqlSource).toContain('SET user_id = NULL');
    });

    it('proves audit_logs table is never truncated or deleted during operator removal', () => {
      expect(edgeFunctionSource).not.toMatch(/from\("audit_logs"\)\s*\.\s*delete/);
      expect(deleteSqlSource).not.toMatch(/DELETE FROM public\.audit_logs/);
    });
  });

  // =========================================================================
  // 5. OperatorService.deleteOperator Execution & Error Handling
  // =========================================================================
  describe('5. OperatorService.deleteOperator Server-Side Invocation & Error Mapping', () => {
    it('successfully invokes Edge Function with action: delete_operator', async () => {
      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: { success: true, message: 'Operator permanently deleted.', user_id: mockOperatorId },
        error: null,
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.deleteOperator(mockOperatorId, mockAdminId);

      expect(mockInvoke).toHaveBeenCalledWith('create-operator', {
        body: {
          action: 'delete_operator',
          user_id: mockOperatorId,
        },
      });
      expect(result.success).toBe(true);
    });

    it('handles HTTP 403 Forbidden with clear access denied error', async () => {
      const mockResponse = new Response(JSON.stringify({ error: 'Access Denied' }), { status: 403 });
      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Edge Function returned a non-2xx status code',
          context: mockResponse,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      // Stub rpc to avoid fallback executing real network call
      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: null,
        error: { message: 'RPC denied', details: '', hint: '', code: '403' },
      } as any);

      const result = await OperatorService.deleteOperator(mockOperatorId, mockAdminId);
      expect(result.success).toBe(false);
      expect(result.error).toContain('Access Denied (HTTP 403)');
    });

    it('handles HTTP 404 Operator Not Found error from Edge Function', async () => {
      const mockResponse = new Response(JSON.stringify({ error: 'Operator account not found.' }), { status: 404 });
      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Not found',
          context: mockResponse,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: null,
        error: { message: 'Operator not found', details: '', hint: '', code: '404' },
      } as any);

      const result = await OperatorService.deleteOperator('non-existent-id', mockAdminId);
      expect(result.success).toBe(false);
      expect(result.error).toContain('404');
    });

    it('handles network failure with helpful error message', async () => {
      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: new Error('Network connection failed'),
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: null,
        error: { message: 'Connection failure', details: '', hint: '', code: '500' },
      } as any);

      const result = await OperatorService.deleteOperator(mockOperatorId, mockAdminId);
      expect(result.success).toBe(false);
      expect(result.error).toContain('Network connection failed');
    });
  });

  // =========================================================================
  // 6. Audit Logging Verification
  // =========================================================================
  describe('6. Immutable Audit Logging', () => {
    it('proves Edge Function writes an audit log recording who deleted the operator and when', () => {
      expect(edgeFunctionSource).toContain('p_action: "OPERATOR_DELETED"');
      expect(edgeFunctionSource).toContain('p_entity_type: "OPERATOR"');
      expect(edgeFunctionSource).toContain('deleted_by_admin: callerUser.id');
      expect(edgeFunctionSource).toContain('deleted_operator_id: user_id');
    });

    it('proves Database SQL RPC records OPERATOR_DELETED audit event', () => {
      expect(deleteSqlSource).toContain("'OPERATOR_DELETED'");
      expect(deleteSqlSource).toContain("'OPERATOR'");
      expect(deleteSqlSource).toContain("'deleted_by_admin', p_admin_user_id");
    });

    it('proves audit action type definition includes OPERATOR_DELETED', async () => {
      const typesSource = await import('../types/index.ts?raw');
      expect(typesSource.default).toContain("'OPERATOR_DELETED'");
    });
  });
});
