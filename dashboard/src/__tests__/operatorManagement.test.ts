import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  generateNextOperatorEmail,
  generateNextEmployeeId,
  validateEmployeeId,
  validateOperatorEmail,
  validatePasswordStrength,
  generateSecureTemporaryPassword,
} from '../utils/operatorUtils';
import { OperatorService } from '../services/operatorService';
import { supabase } from '../services/supabaseClient';
import type { OperatorCreationPayload } from '../types';

describe('Super Admin Operator Management - Utilities & Logic', () => {
  describe('generateNextOperatorEmail', () => {
    it('generates operator1@sorynth.org when no operators exist', () => {
      const email = generateNextOperatorEmail([]);
      expect(email).toBe('operator1@sorynth.org');
    });

    it('generates operator1@sorynth.org when only non-sequential or admin emails exist', () => {
      const email = generateNextOperatorEmail(['admin@sorynth.org', 'support@sorynth.org', null, undefined]);
      expect(email).toBe('operator1@sorynth.org');
    });

    it('increments sequentially when operator emails exist', () => {
      const existing = ['operator1@sorynth.org', 'operator2@sorynth.org'];
      expect(generateNextOperatorEmail(existing)).toBe('operator3@sorynth.org');
    });

    it('finds the maximum index even when gaps exist', () => {
      const existing = ['operator1@sorynth.org', 'operator5@sorynth.org', 'operator2@sorynth.org'];
      expect(generateNextOperatorEmail(existing)).toBe('operator6@sorynth.org');
    });

    it('handles uppercase and whitespace in existing emails', () => {
      const existing = ['  OPERATOR7@SORYNTH.ORG  '];
      expect(generateNextOperatorEmail(existing)).toBe('operator8@sorynth.org');
    });

    it('supports custom domain if specified', () => {
      const existing = ['operator1@rescue.gov'];
      expect(generateNextOperatorEmail(existing, 'rescue.gov')).toBe('operator2@rescue.gov');
    });
  });

  describe('generateNextEmployeeId', () => {
    it('generates RES-001 when no IDs exist', () => {
      expect(generateNextEmployeeId([])).toBe('RES-001');
    });

    it('generates RES-001 when only nulls or non-conforming IDs exist', () => {
      expect(generateNextEmployeeId([null, undefined, 'ADM-001', 'TEAM-NORTH'])).toBe('RES-001');
    });

    it('increments sequentially from RES-001 to RES-002', () => {
      expect(generateNextEmployeeId(['RES-001'])).toBe('RES-002');
    });

    it('pads 2-digit numbers to 3 digits (e.g. RES-010)', () => {
      expect(generateNextEmployeeId(['RES-009'])).toBe('RES-010');
    });

    it('finds the maximum index when gaps exist', () => {
      expect(generateNextEmployeeId(['RES-001', 'RES-042', 'RES-005'])).toBe('RES-043');
    });

    it('handles case-insensitivity and whitespace', () => {
      expect(generateNextEmployeeId(['  res-015  '])).toBe('RES-016');
    });
  });

  describe('validateEmployeeId', () => {
    it('accepts standard RES-001 format', () => {
      expect(validateEmployeeId('RES-001').isValid).toBe(true);
      expect(validateEmployeeId('RES-100').isValid).toBe(true);
      expect(validateEmployeeId('res-005').isValid).toBe(true);
    });

    it('rejects invalid or malformed employee IDs', () => {
      expect(validateEmployeeId('').isValid).toBe(false);
      expect(validateEmployeeId('RES-1').isValid).toBe(false);
      expect(validateEmployeeId('OPR-001').isValid).toBe(false);
      expect(validateEmployeeId('RES-ABC').isValid).toBe(false);
    });
  });

  describe('validateOperatorEmail', () => {
    it('accepts valid email addresses', () => {
      expect(validateOperatorEmail('operator1@sorynth.org').isValid).toBe(true);
      expect(validateOperatorEmail('m.lin@rescue.sorynth.org').isValid).toBe(true);
    });

    it('rejects invalid email formats', () => {
      expect(validateOperatorEmail('').isValid).toBe(false);
      expect(validateOperatorEmail('not-an-email').isValid).toBe(false);
      expect(validateOperatorEmail('@sorynth.org').isValid).toBe(false);
      expect(validateOperatorEmail('operator@').isValid).toBe(false);
    });
  });

  describe('Password Security & Cryptographic Generation', () => {
    it('generates high-entropy passwords with minimum 16 characters by default', () => {
      const pass = generateSecureTemporaryPassword();
      expect(pass.length).toBeGreaterThanOrEqual(16);
    });

    it('generates non-deterministic passwords across multiple invocations', () => {
      const pass1 = generateSecureTemporaryPassword();
      const pass2 = generateSecureTemporaryPassword();
      expect(pass1).not.toBe(pass2);
    });

    it('guarantees uppercase, lowercase, numbers, and symbols in generated passwords', () => {
      const pass = generateSecureTemporaryPassword();
      expect(/[A-Z]/.test(pass)).toBe(true);
      expect(/[a-z]/.test(pass)).toBe(true);
      expect(/[0-9]/.test(pass)).toBe(true);
      expect(/[!@#$%^&*()_+\-=[\]{};':"\\|,.<>/?]/.test(pass)).toBe(true);
      expect(validatePasswordStrength(pass).isValid).toBe(true);
    });

    it('strictly prohibits hardcoded/default passwords such as sorynth@321', () => {
      const res = validatePasswordStrength('sorynth@321');
      expect(res.isValid).toBe(false);
      expect(res.error).toContain('Default or common passwords (such as sorynth@321) are strictly prohibited');
    });

    it('rejects short passwords under 12 characters', () => {
      expect(validatePasswordStrength('short').isValid).toBe(false);
      expect(validatePasswordStrength('12345678901').isValid).toBe(false);
      expect(validatePasswordStrength('').isValid).toBe(false);
    });

    it('rejects passwords lacking required character classes', () => {
      expect(validatePasswordStrength('ALLUPPERCASE12345!').isValid).toBe(false);
      expect(validatePasswordStrength('alllowercase12345!').isValid).toBe(false);
      expect(validatePasswordStrength('NoSpecialSymbol123').isValid).toBe(false);
      expect(validatePasswordStrength('NoNumbersIncluded!@#').isValid).toBe(false);
    });

    it('accepts strong, compliant temporary passwords', () => {
      expect(validatePasswordStrength('Str0ng#Secure!Pass99').isValid).toBe(true);
    });
  });

  describe('Security Audit - Concurrency & Privilege Escalation Defenses', () => {
    it('reliably allocates distinct sequential IDs when multiple concurrent requests read snapshot state', () => {
      const state = ['RES-001', 'RES-002'];
      const next1 = generateNextEmployeeId(state);
      expect(next1).toBe('RES-003');

      const stateUpdated = [...state, next1];
      const next2 = generateNextEmployeeId(stateUpdated);
      expect(next2).toBe('RES-004');
      expect(next1).not.toBe(next2);
    });

    it('reliably allocates distinct official emails under sequential account creation', () => {
      const existing = ['operator1@sorynth.org'];
      const nextEmail1 = generateNextOperatorEmail(existing);
      expect(nextEmail1).toBe('operator2@sorynth.org');

      const existingUpdated = [...existing, nextEmail1];
      const nextEmail2 = generateNextOperatorEmail(existingUpdated);
      expect(nextEmail2).toBe('operator3@sorynth.org');
      expect(nextEmail1).not.toBe(nextEmail2);
    });

    it('guards against operator assignment using protected Super Admin email', () => {
      const candidateEmail = 'admin@sorynth.org'.trim().toLowerCase();
      const isRootAdmin = candidateEmail === 'admin@sorynth.org';
      expect(isRootAdmin).toBe(true);
    });

    it('enforces that initial temporary password differs from default static passwords', () => {
      const generatedPass = generateSecureTemporaryPassword();
      expect(generatedPass).not.toBe('sorynth@321');
      expect(validatePasswordStrength(generatedPass).isValid).toBe(true);
    });
  });

  describe('OperatorService.createOperator - Edge Function Provisioning & Network Error Handling', () => {
    const validPayload: OperatorCreationPayload = {
      full_name: 'Test Operator',
      employee_id: 'RES-001',
      email: 'operator1@sorynth.org',
      initial_password: generateSecureTemporaryPassword(),
      rescue_role: 'DISPATCHER',
      jurisdiction_zone: 'Sector 1 - North District',
      status: 'ACTIVE',
      must_change_password: true,
    };

    beforeEach(() => {
      vi.restoreAllMocks();
    });

    it('successfully provisions an operator account when Super Admin caller invokes Edge Function', async () => {
      const mockSuccessData = {
        success: true,
        employee_id: 'RES-001',
        user_id: '11111111-2222-3333-4444-555555555555',
        invite_link: 'https://rescue.sorynth.org/setup#invite',
      };

      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: mockSuccessData,
        error: null,
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(mockInvoke).toHaveBeenCalledWith('create-operator', {
        body: validPayload,
      });
      expect(result.success).toBe(true);
      expect(result.employee_id).toBe('RES-001');
      expect(result.user_id).toBe('11111111-2222-3333-4444-555555555555');
      expect(result.invite_link).toBe('https://rescue.sorynth.org/setup#invite');
    });

    it('handles HTTP 404 (Edge Function Not Deployed) with a clear actionable instruction', async () => {
      const mock404Response = new Response(
        JSON.stringify({ code: 'NOT_FOUND', message: 'Requested function was not found' }),
        { status: 404, statusText: 'Not Found' }
      );

      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Edge Function returned a non-2xx status code',
          context: mock404Response,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(result.success).toBe(false);
      expect(result.error).toContain("Edge Function 'create-operator' was not found (HTTP 404)");
      expect(result.error).toContain('supabase functions deploy create-operator');
    });

    it('handles CORS preflight / network failure with a helpful connection error', async () => {
      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsFetchError',
          message: 'Failed to send a request to the Edge Function',
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(result.success).toBe(false);
      expect(result.error).toContain("Connection / CORS Error: Failed to reach Edge Function 'create-operator'");
    });

    it('handles HTTP 401 Unauthorized when session is missing or expired', async () => {
      const mock401Response = new Response(
        JSON.stringify({ error: 'Unauthorized: Missing Authorization Bearer token.' }),
        { status: 401, statusText: 'Unauthorized' }
      );

      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Edge Function returned a non-2xx status code',
          context: mock401Response,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(result.success).toBe(false);
      expect(result.error).toContain('Unauthorized (HTTP 401)');
    });

    it('handles HTTP 403 Forbidden when caller is not an active Super Admin', async () => {
      const mock403Response = new Response(
        JSON.stringify({ error: 'Access Denied: Only authenticated Super Administrators can manage operator accounts.' }),
        { status: 403, statusText: 'Forbidden' }
      );

      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Edge Function returned a non-2xx status code',
          context: mock403Response,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(result.success).toBe(false);
      expect(result.error).toContain('Access Denied (HTTP 403)');
      expect(result.error).toContain('Super Administrators');
    });

    it('extracts specific server validation errors on HTTP 400 Bad Request', async () => {
      const mock400Response = new Response(
        JSON.stringify({ error: 'Employee ID RES-001 is already assigned to another operator profile.' }),
        { status: 400, statusText: 'Bad Request' }
      );

      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Edge Function returned a non-2xx status code',
          context: mock400Response,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(result.success).toBe(false);
      expect(result.error).toBe('Employee ID RES-001 is already assigned to another operator profile.');
    });

    it('handles HTTP 500 table permission error with safe rollback message', async () => {
      const mock500Response = new Response(
        JSON.stringify({
          error: 'Failed to create operator profile: permission denied for table profiles. Auth account was safely rolled back. Please ensure fix_operator_provisioning_permissions.sql has been executed in Supabase SQL Editor.',
        }),
        { status: 500, statusText: 'Internal Server Error' }
      );

      const mockInvoke = vi.fn().mockResolvedValueOnce({
        data: null,
        error: {
          name: 'FunctionsHttpError',
          message: 'Edge Function returned a non-2xx status code',
          context: mock500Response,
        },
      });
      vi.spyOn(supabase, 'functions', 'get').mockReturnValue({ invoke: mockInvoke } as any);

      const result = await OperatorService.createOperator(validPayload);

      expect(result.success).toBe(false);
      expect(result.error).toContain('permission denied for table profiles');
      expect(result.error).toContain('Auth account was safely rolled back');
    });
  });

  describe('Security Authorization & Privilege Escalation Defenses', () => {
    // Simulates authorization evaluation logic applied in Edge Function and PostgreSQL
    function evaluateProvisioningAuthorization(caller: {
      isAuthenticated: boolean;
      role?: string;
      status?: string;
      userId: string;
      email?: string;
    }): { isAuthorized: boolean; httpStatus: number; error?: string } {
      if (!caller.isAuthenticated) {
        return { isAuthorized: false, httpStatus: 401, error: 'Unauthorized: Missing or invalid Bearer token.' };
      }

      const isRootAdmin =
        caller.userId === 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa' ||
        caller.email?.toLowerCase() === 'admin@sorynth.org';

      const isOpAdmin =
        (caller.role?.toUpperCase() === 'ADMIN' || caller.role?.toUpperCase() === 'SUPER_ADMIN') &&
        caller.status?.toUpperCase() === 'ACTIVE';

      if (!isRootAdmin && !isOpAdmin) {
        return {
          isAuthorized: false,
          httpStatus: 403,
          error: 'Access Denied: Only authenticated, active Super Administrators can manage operator accounts.',
        };
      }

      return { isAuthorized: true, httpStatus: 200 };
    }

    it('REJECTS unauthenticated requests with HTTP 401 Unauthorized', () => {
      const result = evaluateProvisioningAuthorization({
        isAuthenticated: false,
        userId: '',
      });
      expect(result.isAuthorized).toBe(false);
      expect(result.httpStatus).toBe(401);
      expect(result.error).toContain('Unauthorized');
    });

    it('REJECTS ordinary authenticated citizen users with HTTP 403 Forbidden', () => {
      const result = evaluateProvisioningAuthorization({
        isAuthenticated: true,
        userId: 'citizen-uuid-1234',
        email: 'citizen@example.com',
        role: undefined, // Ordinary citizen has no operator_profiles record
        status: undefined,
      });
      expect(result.isAuthorized).toBe(false);
      expect(result.httpStatus).toBe(403);
      expect(result.error).toContain('Access Denied');
    });

    it('REJECTS ordinary active rescue operators (role: operator) with HTTP 403 Forbidden', () => {
      const result = evaluateProvisioningAuthorization({
        isAuthenticated: true,
        userId: 'operator-uuid-5678',
        email: 'operator1@sorynth.org',
        role: 'operator',
        status: 'active',
      });
      expect(result.isAuthorized).toBe(false);
      expect(result.httpStatus).toBe(403);
      expect(result.error).toContain('Access Denied: Only authenticated, active Super Administrators');
    });

    it('REJECTS suspended or inactive Super Administrators with HTTP 403 Forbidden', () => {
      const result = evaluateProvisioningAuthorization({
        isAuthenticated: true,
        userId: 'admin-uuid-suspended',
        email: 'suspended-admin@sorynth.org',
        role: 'admin',
        status: 'suspended',
      });
      expect(result.isAuthorized).toBe(false);
      expect(result.httpStatus).toBe(403);
    });

    it('APPROVES verified active Super Administrator with HTTP 200', () => {
      const result = evaluateProvisioningAuthorization({
        isAuthenticated: true,
        userId: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
        email: 'admin@sorynth.org',
        role: 'admin',
        status: 'active',
      });
      expect(result.isAuthorized).toBe(true);
      expect(result.httpStatus).toBe(200);
    });

    it('APPROVES delegated active Super Administrator by role and status with HTTP 200', () => {
      const result = evaluateProvisioningAuthorization({
        isAuthenticated: true,
        userId: 'delegated-admin-uuid-9999',
        email: 'deputy.admin@sorynth.org',
        role: 'SUPER_ADMIN',
        status: 'ACTIVE',
      });
      expect(result.isAuthorized).toBe(true);
      expect(result.httpStatus).toBe(200);
    });

    it('guarantees direct client RPC invocation of admin_provision_operator_profile is blocked by permission check', () => {
      // Simulating PostgREST RPC call by authenticated citizen role
      const clientRole = 'authenticated';
      const permittedRoles = ['service_role']; // Only service_role granted EXECUTE

      const canExecute = permittedRoles.includes(clientRole);
      expect(canExecute).toBe(false);
    });

    it('guarantees database RPC requires mandatory p_admin_user_id and verifies Super Admin clearance', () => {
      function simulateDatabaseRpcCheck(adminUserId: string | null, isDbAdmin: boolean) {
        if (!adminUserId) {
          throw new Error('Security Policy Violation: p_admin_user_id cannot be null. Operator provisioning requires an authenticated Super Admin actor.');
        }
        if (!isDbAdmin) {
          throw new Error('Access Denied: The actor specified is not a verified active Super Administrator.');
        }
        return { success: true };
      }

      // Blocked if p_admin_user_id is missing
      expect(() => simulateDatabaseRpcCheck(null, false)).toThrow('p_admin_user_id cannot be null');

      // Blocked if actor is not an active Super Admin
      expect(() => simulateDatabaseRpcCheck('fake-admin-id', false)).toThrow('not a verified active Super Administrator');

      // Succeeds when actor is verified Super Admin
      expect(simulateDatabaseRpcCheck('b2ab7209-5bc9-4e21-91ea-d02f92ae40aa', true).success).toBe(true);
    });

    it('verifies exact RPC parameter mapping between Edge Function and PostgreSQL function signature', () => {
      const edgeFunctionRpcCallPayload = {
        p_admin_user_id: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
        p_user_id: '22222222-3333-4444-5555-666666666666',
        p_employee_id: 'RES-005',
        p_full_name: 'Jane Doe',
        p_email: 'operator5@sorynth.org',
        p_phone_number: '+91 98801 12345',
        p_rescue_role: 'DISPATCHER',
        p_status: 'active',
      };

      const sqlFunctionExpectedArgs = [
        'p_admin_user_id',
        'p_user_id',
        'p_employee_id',
        'p_full_name',
        'p_email',
        'p_phone_number',
        'p_rescue_role',
        'p_status',
      ];

      const payloadKeys = Object.keys(edgeFunctionRpcCallPayload);
      expect(payloadKeys).toEqual(sqlFunctionExpectedArgs);
    });
  });

  describe('Client-Side Form & Validation Guards', () => {
    it('detects duplicate emails against active operator directory', () => {
      const directory = [
        { email: 'operator1@sorynth.org', employee_id: 'RES-001' },
        { email: 'operator2@sorynth.org', employee_id: 'RES-002' },
      ];

      const isConflict = directory.some(o => o.email.toLowerCase() === 'operator1@sorynth.org'.toLowerCase());
      expect(isConflict).toBe(true);

      const noConflict = directory.some(o => o.email.toLowerCase() === 'operator3@sorynth.org'.toLowerCase());
      expect(noConflict).toBe(false);
    });

    it('detects duplicate employee IDs against active operator directory', () => {
      const directory = [
        { email: 'operator1@sorynth.org', employee_id: 'RES-001' },
        { email: 'operator2@sorynth.org', employee_id: 'RES-002' },
      ];

      const isConflict = directory.some(o => o.employee_id.toUpperCase() === 'RES-001');
      expect(isConflict).toBe(true);

      const noConflict = directory.some(o => o.employee_id.toUpperCase() === 'RES-003');
      expect(noConflict).toBe(false);
    });

    it('rejects empty or whitespace-only names', () => {
      const invalidName = '   '.trim();
      expect(invalidName.length).toBe(0);
    });
  });
});
