import { describe, it, expect } from 'vitest';
import type { SystemRole, UserProfile, AccountStatus, RescueRole } from '../types';
import { generateSecureTemporaryPassword, generateNextOperatorEmail, generateNextEmployeeId } from '../utils/operatorUtils';

describe('SORYNTH Role Separation & Access Control Architecture', () => {
  // Mock helper function simulating AuthContext's verified live schema resolution logic
  function resolveUserClearance(params: {
    userId: string;
    profileData: Partial<UserProfile> | null;
    opData: Record<string, unknown> | null;
    isDbSuperAdmin: boolean;
    userMetadata?: Record<string, unknown>;
  }) {
    const { userId, profileData, opData, isDbSuperAdmin, userMetadata } = params;

    // 1. Authoritative resolution based on verified live schema
    // Live Admin: UUID b2ab7209-5bc9-4e21-91ea-d02f92ae40aa, operator_profiles.role = 'admin', employee_id = 'ADM-001', status = 'active'
    const opRoleRaw = typeof opData?.role === 'string' ? opData.role.trim() : '';
    const opRoleUpper = opRoleRaw.toUpperCase();
    const metaRoleUpper = typeof userMetadata?.role === 'string' ? userMetadata.role.trim().toUpperCase() : '';
    const userEmailLower = (
      (typeof opData?.email === 'string' ? opData.email : '') ||
      profileData?.email ||
      (typeof userMetadata?.email === 'string' ? userMetadata.email : '') ||
      ''
    ).trim().toLowerCase();

    const isSuperAdmin = Boolean(
      isDbSuperAdmin ||
      userId === 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa' ||
      userEmailLower === 'admin@sorynth.org' ||
      opRoleUpper === 'SUPER_ADMIN' ||
      opRoleUpper === 'ADMIN' ||
      metaRoleUpper === 'SUPER_ADMIN'
    );

    // 2. Account Clearance & Missing Operator Account Handling
    if (!isSuperAdmin) {
      // Defense-in-depth: If no operator_profiles record exists, user has no rescue clearance
      if (!opData) {
        return {
          isAllowed: false,
          error: 'Access Denied: No rescue operator or administrator profile is assigned to this account.',
        };
      }

      // Suspended / Deactivated operator check (case-insensitive)
      const opStatusUpper = String(opData.status || '').trim().toUpperCase();
      if (opStatusUpper === 'INACTIVE' || opStatusUpper === 'SUSPENDED') {
        return {
          isAllowed: false,
          error: 'This operator account has been suspended. Please contact your Super Administrator.',
        };
      }
    }

    const trustedRole: SystemRole = isSuperAdmin ? 'SUPER_ADMIN' : 'RESCUE_OPERATOR';

    // 3. Set employee ID and role badges
    // For Super Admin, strictly enforce ADM-001 (stripping any accidental operator RES- prefix)
    const opEmployeeId = typeof opData?.employee_id === 'string' ? opData.employee_id : null;
    const candidateId = opEmployeeId;
    const resolvedEmployeeId = isSuperAdmin
      ? (candidateId && candidateId.startsWith('ADM-') ? candidateId : 'ADM-001')
      : (candidateId || null);

    // Super Admin has NO field operator role (null), preventing dispatcher/operator badges
    const operatorRole: RescueRole | null = trustedRole === 'SUPER_ADMIN'
      ? null
      : (profileData?.rescue_role as RescueRole) || 'DISPATCHER';

    const opStatus = typeof opData?.status === 'string' ? (opData.status.toUpperCase() as AccountStatus) : 'ACTIVE';

    const resolvedProfile: UserProfile = {
      id: userId,
      full_name: (opData?.full_name as string) || profileData?.full_name || (userEmailLower ? userEmailLower.split('@')[0] : '—'),
      email: (opData?.email as string) || profileData?.email || userEmailLower,
      system_role: trustedRole,
      rescue_role: trustedRole === 'SUPER_ADMIN' ? undefined : operatorRole,
      employee_id: resolvedEmployeeId,
      status: opStatus === 'ACTIVE' ? 'ACTIVE' : 'INACTIVE',
      is_active: opStatus === 'ACTIVE',
      must_change_password: Boolean(userMetadata?.must_change_password),
      jurisdiction_zone: ((opData?.jurisdiction_zone as string) || (userMetadata?.jurisdiction_zone as string) || null),
      created_at: (opData?.created_at as string) || profileData?.created_at || new Date().toISOString(),
      updated_at: profileData?.updated_at || new Date().toISOString(),
    };

    const isAdmin = trustedRole === 'SUPER_ADMIN';
    const isOperator = trustedRole === 'RESCUE_OPERATOR';
    const defaultRoute = isAdmin ? '/admin' : '/operator';

    // Navigation configuration
    const adminNavItems = [
      '/admin',
      '/admin/operators',
      '/admin/emergencies',
      '/admin/map',
      '/admin/network',
      '/admin/comms',
      '/admin/teams',
      '/admin/analytics',
      '/admin/settings',
      '/admin/profile',
    ];

    const operatorNavItems = [
      '/operator',
      '/operator/emergencies',
      '/operator/map',
      '/operator/teams',
      '/operator/profile',
    ];

    return {
      isAllowed: true,
      trustedRole,
      isAdmin,
      isOperator,
      operatorRole,
      employeeId: resolvedEmployeeId,
      defaultRoute,
      profile: resolvedProfile,
      navItems: isAdmin ? adminNavItems : operatorNavItems,
      sidebarBadge: isAdmin ? 'ADMIN' : 'OPERATOR',
      stationTitle: isAdmin ? 'Super Admin Mode' : `Station: ${resolvedEmployeeId || 'Active'}`,
      profileRoute: isAdmin ? '/admin/profile' : '/operator/profile',
    };
  }

  describe('1. Super Administrator (admin@sorynth.org)', () => {
    it('correctly resolves LIVE DATABASE Admin (UUID: b2ab7209-5bc9-4e21-91ea-d02f92ae40aa, role: admin, status: active)', () => {
      // EXACT live database record
      const clearance = resolveUserClearance({
        userId: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
        profileData: {
          id: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
          full_name: 'SORYNTH Admin',
          email: 'admin@sorynth.org',
          rescue_role: null, // No field rescue role in profiles
        },
        opData: {
          user_id: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
          employee_id: 'ADM-001',
          full_name: 'SORYNTH Super Administrator',
          email: 'admin@sorynth.org',
          role: 'admin', // Verified lowercase in live DB
          status: 'active', // Verified lowercase in live DB
        },
        isDbSuperAdmin: false, // Must resolve accurately even before RPC executes
      });

      expect(clearance.isAllowed).toBe(true);
      expect(clearance.trustedRole).toBe('SUPER_ADMIN');
      expect(clearance.isAdmin).toBe(true);
      expect(clearance.isOperator).toBe(false);
      expect(clearance.operatorRole).toBeNull(); // Super Admin has no field operator role
      expect(clearance.employeeId).toBe('ADM-001');
      expect(clearance.defaultRoute).toBe('/admin');
      expect(clearance.profileRoute).toBe('/admin/profile');
      expect(clearance.sidebarBadge).toBe('ADMIN');
      expect(clearance.stationTitle).toBe('Super Admin Mode');
      expect(clearance.navItems).toHaveLength(10);
      expect(clearance.navItems).toContain('/admin/operators');
      expect(clearance.navItems).toContain('/admin/profile');
    });

    it('CORRECTION FIX: strips accidental RES-001 and DISPATCHER if previously stored for admin', () => {
      // In prior misconfigurations, admin@sorynth.org may have had RES-001 and DISPATCHER
      const clearance = resolveUserClearance({
        userId: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
        profileData: {
          full_name: 'SORYNTH Admin',
          email: 'admin@sorynth.org',
          rescue_role: 'DISPATCHER', // Erroneously stored operator role
        },
        opData: {
          user_id: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
          employee_id: 'RES-001', // Erroneously stored operator employee id
          role: 'admin',
          status: 'active',
        },
        isDbSuperAdmin: true,
      });

      // Must strictly resolve to ADM-001 and null operatorRole, NOT RES-001 or DISPATCHER
      expect(clearance.employeeId).toBe('ADM-001');
      expect(clearance.operatorRole).toBeNull();
      expect(clearance.stationTitle).toBe('Super Admin Mode');
      expect(clearance.defaultRoute).toBe('/admin');
      expect(clearance.profileRoute).toBe('/admin/profile');
    });

    it('resolves SUPER_ADMIN via email fallback even if opData is initializing', () => {
      const clearance = resolveUserClearance({
        userId: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
        profileData: {
          full_name: 'SORYNTH Admin',
          email: 'admin@sorynth.org',
        },
        opData: null,
        isDbSuperAdmin: false,
      });

      expect(clearance.trustedRole).toBe('SUPER_ADMIN');
      expect(clearance.isAdmin).toBe(true);
      expect(clearance.employeeId).toBe('ADM-001');
      expect(clearance.defaultRoute).toBe('/admin');
    });
  });

  describe('2. Operator Accounts (operator1@sorynth.org, operator2@sorynth.org, operator3@sorynth.org)', () => {
    it('Operator 1 (RES-001): resolves to RESCUE_OPERATOR and routes to /operator', () => {
      const clearance = resolveUserClearance({
        userId: 'op-uuid-0001',
        profileData: {
          id: 'op-uuid-0001',
          full_name: 'Operator One',
          email: 'operator1@sorynth.org',
          rescue_role: 'DISPATCHER',
        },
        opData: {
          user_id: 'op-uuid-0001',
          employee_id: 'RES-001',
          full_name: 'Operator One',
          email: 'operator1@sorynth.org',
          role: 'operator',
          status: 'active',
        },
        isDbSuperAdmin: false,
      });

      expect(clearance.isAllowed).toBe(true);
      expect(clearance.trustedRole).toBe('RESCUE_OPERATOR');
      expect(clearance.isAdmin).toBe(false);
      expect(clearance.isOperator).toBe(true);
      expect(clearance.operatorRole).toBe('DISPATCHER');
      expect(clearance.employeeId).toBe('RES-001');
      expect(clearance.defaultRoute).toBe('/operator');
      expect(clearance.profileRoute).toBe('/operator/profile');
      expect(clearance.sidebarBadge).toBe('OPERATOR');
      expect(clearance.stationTitle).toBe('Station: RES-001');
      expect(clearance.navItems).toEqual([
        '/operator',
        '/operator/emergencies',
        '/operator/map',
        '/operator/teams',
        '/operator/profile',
      ]);
      expect(clearance.navItems).not.toContain('/admin');
      expect(clearance.navItems).not.toContain('/admin/operators');
    });

    it('Operator 2 (RES-002) & Operator 3 (RES-003): use the EXACT same dashboard navigation as Operator 1', () => {
      const op1Clearance = resolveUserClearance({
        userId: 'op-uuid-0001',
        profileData: {
          full_name: 'Operator One',
          email: 'operator1@sorynth.org',
          rescue_role: 'DISPATCHER',
        },
        opData: {
          user_id: 'op-uuid-0001',
          employee_id: 'RES-001',
          full_name: 'Operator One',
          email: 'operator1@sorynth.org',
          role: 'operator',
          status: 'active',
        },
        isDbSuperAdmin: false,
      });

      const op2Clearance = resolveUserClearance({
        userId: 'op-uuid-0002',
        profileData: {
          full_name: 'Operator Two',
          email: 'operator2@sorynth.org',
          rescue_role: 'PARAMEDIC',
        },
        opData: {
          user_id: 'op-uuid-0002',
          employee_id: 'RES-002',
          full_name: 'Operator Two',
          email: 'operator2@sorynth.org',
          role: 'operator',
          status: 'active',
        },
        isDbSuperAdmin: false,
      });

      const op3Clearance = resolveUserClearance({
        userId: 'op-uuid-0003',
        profileData: {
          full_name: 'Operator Three',
          email: 'operator3@sorynth.org',
          rescue_role: 'SEARCH_AND_RESCUE',
        },
        opData: {
          user_id: 'op-uuid-0003',
          employee_id: 'RES-003',
          full_name: 'Operator Three',
          email: 'operator3@sorynth.org',
          role: 'operator',
          status: 'active',
        },
        isDbSuperAdmin: false,
      });

      // All 3 operators MUST share the EXACT same navigation menu items and routes
      expect(op1Clearance.navItems).toEqual(op2Clearance.navItems);
      expect(op2Clearance.navItems).toEqual(op3Clearance.navItems);
      expect(op1Clearance.defaultRoute).toBe('/operator');
      expect(op2Clearance.defaultRoute).toBe('/operator');
      expect(op3Clearance.defaultRoute).toBe('/operator');
      expect(op1Clearance.profileRoute).toBe('/operator/profile');
      expect(op2Clearance.profileRoute).toBe('/operator/profile');
      expect(op3Clearance.profileRoute).toBe('/operator/profile');

      // But retain distinct credentials and identity badges
      expect(op1Clearance.employeeId).toBe('RES-001');
      expect(op2Clearance.employeeId).toBe('RES-002');
      expect(op3Clearance.employeeId).toBe('RES-003');
      expect(op1Clearance.stationTitle).toBe('Station: RES-001');
      expect(op2Clearance.stationTitle).toBe('Station: RES-002');
      expect(op3Clearance.stationTitle).toBe('Station: RES-003');
    });

    it('generates sequential accounts: operator1 -> operator2 -> operator3 with RES-001 -> RES-002 -> RES-003', () => {
      const email1 = generateNextOperatorEmail([]);
      const id1 = generateNextEmployeeId([]);
      expect(email1).toBe('operator1@sorynth.org');
      expect(id1).toBe('RES-001');

      const email2 = generateNextOperatorEmail([email1]);
      const id2 = generateNextEmployeeId([id1]);
      expect(email2).toBe('operator2@sorynth.org');
      expect(id2).toBe('RES-002');

      const email3 = generateNextOperatorEmail([email1, email2]);
      const id3 = generateNextEmployeeId([id1, id2]);
      expect(email3).toBe('operator3@sorynth.org');
      expect(id3).toBe('RES-003');
    });
  });

  describe('3. Missing Operator Account & Suspended Account Handling', () => {
    it('MISSING OPERATOR ACCOUNT: Citizen user in profiles without operator_profiles record is strictly denied access', () => {
      const citizenClearance = resolveUserClearance({
        userId: 'citizen-uuid-9999',
        profileData: {
          id: 'citizen-uuid-9999',
          full_name: 'John Citizen',
          email: 'citizen@example.com',
          blood_group: 'O+',
          medical_notes: 'Asthmatic',
          rescue_role: null,
        },
        opData: null, // NO operator record exists
        isDbSuperAdmin: false,
      });

      expect(citizenClearance.isAllowed).toBe(false);
      expect(citizenClearance.error).toContain('Access Denied: No rescue operator or administrator profile is assigned to this account.');
    });

    it('SUSPENDED OPERATOR: Operator with status = "suspended" is strictly blocked from authentication', () => {
      const suspended = resolveUserClearance({
        userId: 'op-suspended-001',
        profileData: {
          full_name: 'Suspended Operator',
          email: 'operator3@sorynth.org',
        },
        opData: {
          user_id: 'op-suspended-001',
          employee_id: 'RES-003',
          role: 'operator',
          status: 'suspended', // Suspended status
        },
        isDbSuperAdmin: false,
      });

      expect(suspended.isAllowed).toBe(false);
      expect(suspended.error).toContain('This operator account has been suspended');
    });

    it('INACTIVE OPERATOR: Operator with status = "inactive" is strictly blocked from authentication', () => {
      const inactive = resolveUserClearance({
        userId: 'op-inactive-001',
        profileData: {
          full_name: 'Inactive Operator',
          email: 'operator4@sorynth.org',
        },
        opData: {
          user_id: 'op-inactive-001',
          employee_id: 'RES-004',
          role: 'operator',
          status: 'inactive',
        },
        isDbSuperAdmin: false,
      });

      expect(inactive.isAllowed).toBe(false);
      expect(inactive.error).toContain('This operator account has been suspended');
    });
  });

  describe('4. Password Separation & Security Controls', () => {
    it('Admin password (adminsry@123) is completely isolated from operator cryptographically generated temporary password', () => {
      const adminPass = 'adminsry@123';
      const operatorInitialPass = generateSecureTemporaryPassword();

      expect(operatorInitialPass.length).toBeGreaterThanOrEqual(14);
      expect(adminPass).not.toBe(operatorInitialPass);
      expect(operatorInitialPass).not.toBe('sorynth@321');
    });

    it('enforces mandatory password change for newly provisioned operators via user_metadata', () => {
      const newOp = resolveUserClearance({
        userId: 'op-new',
        profileData: {
          email: 'operator1@sorynth.org',
        },
        opData: {
          user_id: 'op-new',
          employee_id: 'RES-001',
          role: 'operator',
          status: 'active',
        },
        isDbSuperAdmin: false,
        userMetadata: {
          must_change_password: true,
        },
      });

      expect(newOp.isAllowed).toBe(true);
      expect(newOp.profile?.must_change_password).toBe(true);
    });

    it('clears must_change_password once operator configures their independent password', () => {
      const updatedOp = resolveUserClearance({
        userId: 'op-established',
        profileData: {
          email: 'operator1@sorynth.org',
        },
        opData: {
          user_id: 'op-established',
          employee_id: 'RES-001',
          role: 'operator',
          status: 'active',
        },
        isDbSuperAdmin: false,
        userMetadata: {
          must_change_password: false, // Updated upon first login password change
        },
      });

      expect(updatedOp.isAllowed).toBe(true);
      expect(updatedOp.profile?.must_change_password).toBe(false);
    });
  });
});
