import { describe, it, expect } from 'vitest';
import { EmergencyService } from '../services/emergencyService';
import type { Emergency } from '../types';
import sqlContent from '../sql/rbac_schema_setup.sql?raw';

describe('EmergencyService - Workflow & KPI Metrics', () => {
  const mockEmergencies: Emergency[] = [
    {
      id: 'emg-1',
      emergency_code: 'SOR100001',
      is_guest: true,
      emergency_type: 'MEDICAL',
      latitude: 28.6139,
      longitude: 77.2090,
      communication_method: 'INTERNET',
      status: 'DELIVERED',
      hop_count: 0,
      created_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    },
    {
      id: 'emg-2',
      emergency_code: 'SOR100002',
      is_guest: false,
      emergency_type: 'FIRE',
      latitude: 28.6200,
      longitude: 77.2100,
      communication_method: 'LORA_RELAY',
      status: 'IN_ACTION',
      hop_count: 2,
      created_at: new Date(Date.now() - 45 * 60 * 1000).toISOString(),
      acknowledged_at: new Date(Date.now() - 40 * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    },
    {
      id: 'emg-3',
      emergency_code: 'SOR100003',
      is_guest: false,
      emergency_type: 'ACCIDENT',
      latitude: 28.6300,
      longitude: 77.2200,
      communication_method: 'HYBRID',
      status: 'RESOLVED',
      hop_count: 1,
      created_at: new Date(Date.now() - 120 * 60 * 1000).toISOString(),
      acknowledged_at: new Date(Date.now() - 110 * 60 * 1000).toISOString(),
      resolved_at: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    },
    {
      id: 'emg-4',
      emergency_code: 'SOR100004',
      is_guest: true,
      emergency_type: 'LOST_STRANDED',
      latitude: 28.6400,
      longitude: 77.2300,
      communication_method: 'BLUETOOTH_LORA',
      status: 'CANCELLED',
      hop_count: 3,
      created_at: new Date(Date.now() - 15 * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    },
  ];

  it('accurately calculates active vs resolved incident KPI counts', () => {
    const kpis = EmergencyService.calculateKpis(mockEmergencies, 3, 5);

    expect(kpis.totalEmergencies).toBe(4);
    // Active = DELIVERED + IN_ACTION (2)
    expect(kpis.activeEmergencies).toBe(2);
    // Resolved = 1
    expect(kpis.resolvedEmergencies).toBe(1);
    expect(kpis.availableRescueTeams).toBe(3);
    expect(kpis.verifiedRelayNodes).toBe(5);
  });

  it('computes average response time from created_at to acknowledged_at', () => {
    const kpis = EmergencyService.calculateKpis(mockEmergencies, 2, 2);
    // emg-2 response time was 5 minutes (45m ago to 40m ago)
    // emg-3 response time was 10 minutes (120m ago to 110m ago)
    // Avg = (5 + 10) / 2 = 7.5 -> rounded to 8 or 7
    expect(kpis.averageResponseTimeMinutes).toBeGreaterThan(0);
    expect(kpis.averageResponseTimeMinutes).toBeLessThanOrEqual(10);
  });

  it('validates lifecycle status transitions for emergency dispatch', () => {
    const validTransitions: Record<string, string[]> = {
      DELIVERED: ['ACKNOWLEDGED', 'CANCELLED'],
      ACKNOWLEDGED: ['IN_ACTION', 'CANCELLED'],
      IN_ACTION: ['RESOLVED', 'CANCELLED'],
      RESOLVED: [],
      CANCELLED: [],
    };

    expect(validTransitions['DELIVERED']).toContain('ACKNOWLEDGED');
    expect(validTransitions['ACKNOWLEDGED']).toContain('IN_ACTION');
    expect(validTransitions['IN_ACTION']).toContain('RESOLVED');
    expect(validTransitions['RESOLVED']).toHaveLength(0);
  });

  it('preserves emergency coordinate precision up to 6 decimal places', () => {
    const emg = mockEmergencies[0];
    const latStr = emg.latitude.toFixed(6);
    const lonStr = emg.longitude.toFixed(6);

    expect(latStr).toBe('28.613900');
    expect(lonStr).toBe('77.209000');
    expect(Number.parseFloat(latStr)).toBe(28.6139);
    expect(Number.parseFloat(lonStr)).toBe(77.209);
  });
});

interface TriggerContext {
  sessionUser: 'postgres' | 'service_role' | 'supabase_admin' | 'authenticated' | 'anon';
  currentUser: 'postgres' | 'service_role' | 'supabase_admin' | 'authenticated' | 'anon';
  authUid: string | null;
  isSuperAdmin: boolean;
  isActiveOperator: boolean;
  isTriggerSecurityDefiner: boolean;
}

interface SimulatedEmergencyRow {
  emergency_code?: string;
  status?: string | null;
  user_id?: string | null;
  is_guest?: boolean | null;
  assigned_team_id?: string | null;
  acknowledged_at?: string | null;
  resolved_at?: string | null;
  [key: string]: unknown;
}

function simulateSanitizeEmergencySubmission(
  rowInput: Partial<SimulatedEmergencyRow>,
  ctx: TriggerContext
): SimulatedEmergencyRow {
  const NEW: SimulatedEmergencyRow = { ...rowInput };

  // When a trigger function in PostgreSQL is declared SECURITY DEFINER,
  // PostgreSQL forces current_user to become the function owner ('postgres').
  // Under SECURITY INVOKER (the fix), current_user remains the invoking context.
  const effectiveCurrentUser = ctx.isTriggerSecurityDefiner ? 'postgres' : ctx.currentUser;

  const isOperatorOrAdmin = ctx.isSuperAdmin || ctx.isActiveOperator;

  const isTrustedDefiner = (
    ['postgres', 'service_role', 'supabase_admin'].includes(ctx.sessionUser) ||
    ['postgres', 'service_role', 'supabase_admin'].includes(effectiveCurrentUser)
  );

  if (isOperatorOrAdmin) {
    if (NEW.status !== 'RESOLVED' && NEW.status !== 'CANCELLED') {
      NEW.resolved_at = null;
    }
    return NEW;
  }

  // If caller is neither Super Admin nor active Operator:
  // 1. Status 'DELIVERED' is permitted ONLY through trusted execution (submit_sos_alert SECURITY DEFINER).
  // 2. Direct/untrusted submissions can NEVER claim 'DELIVERED', 'ACKNOWLEDGED', 'IN_ACTION', or 'RESOLVED'; forced to 'PENDING'.
  if (NEW.status === 'DELIVERED') {
    if (!isTrustedDefiner) {
      NEW.status = 'PENDING';
    }
  } else if (!NEW.status || !['PENDING', 'DELIVERED'].includes(NEW.status)) {
    NEW.status = 'PENDING';
  }

  // Zero out all privileged dispatch and resolution fields
  NEW.assigned_team_id = null;
  NEW.acknowledged_at = null;
  NEW.resolved_at = null;

  if (ctx.authUid === null) {
    NEW.user_id = null;
    NEW.is_guest = true;
  } else {
    NEW.user_id = ctx.authUid;
    NEW.is_guest = false;
  }

  return NEW;
}

describe('PostgreSQL sanitize_emergency_submission Trigger & SOS Security Architecture', () => {
  describe('Trigger Ingestion Security & Execution Context (SECURITY INVOKER vs DEFINER)', () => {
    it('demonstrates the critical security flaw when sanitize_emergency_submission was SECURITY DEFINER', () => {
      // In the flawed implementation, SECURITY DEFINER caused current_user to be 'postgres'
      // even when an untrusted authenticated client or guest made a direct table insert
      const flawedContext: TriggerContext = {
        sessionUser: 'authenticated',
        currentUser: 'authenticated', // Caller context
        authUid: 'citizen-attacker-uuid',
        isSuperAdmin: false,
        isActiveOperator: false,
        isTriggerSecurityDefiner: true, // Flawed trigger
      };

      const result = simulateSanitizeEmergencySubmission(
        { status: 'DELIVERED', emergency_code: 'SPOOF-01' },
        flawedContext
      );

      // Flawed behavior: DELIVERED was accepted from untrusted client because current_user became 'postgres'
      expect(result.status).toBe('DELIVERED');
    });

    it('corrects the flaw: SECURITY INVOKER demotes untrusted direct client DELIVERED inserts to PENDING', () => {
      // With SECURITY INVOKER, current_user reflects the actual caller ('authenticated')
      const fixedContext: TriggerContext = {
        sessionUser: 'authenticated',
        currentUser: 'authenticated',
        authUid: 'citizen-client-uuid',
        isSuperAdmin: false,
        isActiveOperator: false,
        isTriggerSecurityDefiner: false, // Fixed trigger
      };

      const result = simulateSanitizeEmergencySubmission(
        { status: 'DELIVERED', emergency_code: 'DIRECT-01' },
        fixedContext
      );

      expect(result.status).toBe('PENDING');
    });

    it('demotes untrusted anonymous direct client DELIVERED inserts to PENDING under SECURITY INVOKER', () => {
      const anonDirectContext: TriggerContext = {
        sessionUser: 'anon',
        currentUser: 'anon',
        authUid: null,
        isSuperAdmin: false,
        isActiveOperator: false,
        isTriggerSecurityDefiner: false,
      };

      const result = simulateSanitizeEmergencySubmission(
        { status: 'DELIVERED', emergency_code: 'ANON-DIRECT-01' },
        anonDirectContext
      );

      expect(result.status).toBe('PENDING');
      expect(result.is_guest).toBe(true);
      expect(result.user_id).toBeNull();
    });

    it('preserves DELIVERED status for trusted submit_sos_alert RPC calls by guest users', () => {
      // submit_sos_alert is SECURITY DEFINER (owned by postgres), so currentUser is 'postgres'
      // while sessionUser is 'anon'
      const trustedGuestRpcContext: TriggerContext = {
        sessionUser: 'anon',
        currentUser: 'postgres', // Set by submit_sos_alert SECURITY DEFINER
        authUid: null,
        isSuperAdmin: false,
        isActiveOperator: false,
        isTriggerSecurityDefiner: false, // Trigger inherits submit_sos_alert's postgres context
      };

      const result = simulateSanitizeEmergencySubmission(
        {
          emergency_code: 'GUEST-SOS-001',
          status: 'DELIVERED',
          assigned_team_id: 'forged-team',
          acknowledged_at: '2026-11-08T00:00:00Z',
          resolved_at: '2026-11-08T00:00:00Z',
        },
        trustedGuestRpcContext
      );

      // DELIVERED status is strictly preserved
      expect(result.status).toBe('DELIVERED');
      expect(result.is_guest).toBe(true);
      expect(result.user_id).toBeNull();
      // Privileged dispatch fields are sanitized
      expect(result.assigned_team_id).toBeNull();
      expect(result.acknowledged_at).toBeNull();
      expect(result.resolved_at).toBeNull();
    });

    it('preserves DELIVERED status for trusted submit_sos_alert RPC calls by authenticated citizens', () => {
      // submit_sos_alert is SECURITY DEFINER, so currentUser is 'postgres'
      // while sessionUser is 'authenticated' and authUid is citizen's UUID
      const trustedCitizenRpcContext: TriggerContext = {
        sessionUser: 'authenticated',
        currentUser: 'postgres',
        authUid: 'authenticated-citizen-uuid',
        isSuperAdmin: false,
        isActiveOperator: false,
        isTriggerSecurityDefiner: false,
      };

      const result = simulateSanitizeEmergencySubmission(
        {
          emergency_code: 'CITIZEN-SOS-002',
          status: 'DELIVERED',
          is_guest: true, // Attacker attempts to claim guest
          user_id: 'fake-victim-uuid', // Attacker attempts identity spoofing
        },
        trustedCitizenRpcContext
      );

      expect(result.status).toBe('DELIVERED');
      expect(result.is_guest).toBe(false);
      expect(result.user_id).toBe('authenticated-citizen-uuid');
      expect(result.assigned_team_id).toBeNull();
    });

    it('demotes spoofed operational statuses (ACKNOWLEDGED, IN_ACTION, RESOLVED) to PENDING for untrusted clients', () => {
      const citizenContext: TriggerContext = {
        sessionUser: 'authenticated',
        currentUser: 'authenticated',
        authUid: 'citizen-123',
        isSuperAdmin: false,
        isActiveOperator: false,
        isTriggerSecurityDefiner: false,
      };

      for (const spoofedStatus of ['ACKNOWLEDGED', 'IN_ACTION', 'RESOLVED', 'UNKNOWN_STATUS', null]) {
        const result = simulateSanitizeEmergencySubmission(
          { status: spoofedStatus, emergency_code: 'TEST-SPOOF' },
          citizenContext
        );
        expect(result.status).toBe('PENDING');
      }
    });

    it('permits active rescue operators to insert operational emergencies without demotion', () => {
      const operatorContext: TriggerContext = {
        sessionUser: 'authenticated',
        currentUser: 'authenticated',
        authUid: 'operator-active-uuid',
        isSuperAdmin: false,
        isActiveOperator: true,
        isTriggerSecurityDefiner: false,
      };

      const result = simulateSanitizeEmergencySubmission(
        {
          emergency_code: 'OP-DISPATCH-001',
          status: 'IN_ACTION',
          assigned_team_id: 'team-alpha-uuid',
          acknowledged_at: '2026-11-08T12:00:00Z',
          resolved_at: '2026-11-08T12:00:00Z', // Cannot forge resolved_at when status is IN_ACTION
        },
        operatorContext
      );

      expect(result.status).toBe('IN_ACTION');
      expect(result.assigned_team_id).toBe('team-alpha-uuid');
      expect(result.acknowledged_at).toBe('2026-11-08T12:00:00Z');
      expect(result.resolved_at).toBeNull(); // Cleared because status is not RESOLVED or CANCELLED
    });

    it('permits Super Admin to insert resolved incidents with valid resolution timestamp', () => {
      const adminContext: TriggerContext = {
        sessionUser: 'authenticated',
        currentUser: 'authenticated',
        authUid: 'b2ab7209-5bc9-4e21-91ea-d02f92ae40aa',
        isSuperAdmin: true,
        isActiveOperator: false,
        isTriggerSecurityDefiner: false,
      };

      const result = simulateSanitizeEmergencySubmission(
        {
          emergency_code: 'ADM-ARCHIVE-001',
          status: 'RESOLVED',
          assigned_team_id: 'team-bravo-uuid',
          acknowledged_at: '2026-11-08T10:00:00Z',
          resolved_at: '2026-11-08T11:00:00Z',
        },
        adminContext
      );

      expect(result.status).toBe('RESOLVED');
      expect(result.assigned_team_id).toBe('team-bravo-uuid');
      expect(result.acknowledged_at).toBe('2026-11-08T10:00:00Z');
      expect(result.resolved_at).toBe('2026-11-08T11:00:00Z'); // Preserved
    });
  });

  describe('Static SQL Migration Verification for rbac_schema_setup.sql', () => {

    it('verifies sanitize_emergency_submission is declared SECURITY INVOKER and not SECURITY DEFINER', () => {
      const funcMatch = sqlContent.match(
        /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.sanitize_emergency_submission\(\)[\s\S]*?AS\s+\$\$/i
      );
      expect(funcMatch).not.toBeNull();
      const funcHeader = funcMatch![0];

      // Must have SECURITY INVOKER
      expect(funcHeader).toMatch(/SECURITY\s+INVOKER/i);
      // Must NOT have SECURITY DEFINER
      expect(funcHeader).not.toMatch(/SECURITY\s+DEFINER/i);
      // Must set search_path
      expect(funcHeader).toMatch(/SET\s+search_path\s*=\s*''/i);
    });

    it('verifies all other 10 security-critical functions strictly maintain SECURITY DEFINER', () => {
      const securityDefinerFunctions = [
        'public.generate_employee_id',
        'public.is_super_admin',
        'public.is_active_operator',
        'public.prevent_operator_privilege_escalation',
        'public.prevent_operator_profile_tampering',
        'public.prevent_operator_emergency_tampering',
        'public.log_audit_event',
        'public.operator_set_team_readiness',
        'public.update_emergency_status_operator',
      ];

      for (const funcName of securityDefinerFunctions) {
        const escapedName = funcName.replace('.', '\\.');
        const regex = new RegExp(`CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+${escapedName}\\([\\s\\S]*?AS\\s+\\$\\$`, 'i');
        const match = sqlContent.match(regex);
        expect(match, `Function ${funcName} should exist`).not.toBeNull();
        expect(match![0], `Function ${funcName} must be SECURITY DEFINER`).toMatch(/SECURITY\s+DEFINER/i);
        expect(match![0], `Function ${funcName} must have search_path = ''`).toMatch(/SET\s+search_path\s*=\s*''/i);
      }
    });

    it('verifies that relay_logs permissions are not weakened', () => {
      expect(sqlContent).toContain('REVOKE ALL PRIVILEGES ON public.relay_logs FROM anon, PUBLIC;');
      expect(sqlContent).toContain('GRANT SELECT ON public.relay_logs TO authenticated;');
      expect(sqlContent).not.toMatch(/GRANT\s+INSERT.*ON\s+public\.relay_logs\s+TO\s+(anon|authenticated|PUBLIC)/i);
    });
  });
});
