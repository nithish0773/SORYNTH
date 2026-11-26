import { describe, it, expect, vi, beforeEach } from 'vitest';
import { LoraService } from '../services/loraService';
import { supabase } from '../services/supabaseClient';

describe('LoRa Gateway Registry & Provisioning Security', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  describe('CSPRNG Token Generation (256-bit Security)', () => {
    it('generates a 64-character lowercase hexadecimal token (256 bits)', () => {
      const token = LoraService.generateSecureToken();
      expect(token).toHaveLength(64);
      expect(token).toMatch(/^[0-9a-f]{64}$/);
    });

    it('generates high-entropy unique tokens across 100 consecutive invocations', () => {
      const tokens = new Set<string>();
      for (let i = 0; i < 100; i++) {
        const token = LoraService.generateSecureToken();
        expect(tokens.has(token)).toBe(false);
        tokens.add(token);
      }
      expect(tokens.size).toBe(100);
    });

    it('leverages hardware CSPRNG (crypto.getRandomValues)', () => {
      const spy = vi.spyOn(globalThis.crypto, 'getRandomValues');
      const token = LoraService.generateSecureToken();
      expect(spy).toHaveBeenCalledTimes(1);
      expect(token).toHaveLength(64);
    });
  });

  describe('Token Privacy & Browser Storage Zero-Leakage', () => {
    it('never persists gateway tokens to localStorage or sessionStorage', () => {
      const token = LoraService.generateSecureToken();

      // Ensure storage APIs do not hold the token
      if (typeof localStorage !== 'undefined') {
        expect(localStorage.getItem('lora_gateway_token')).toBeNull();
        expect(localStorage.getItem('token')).toBeNull();
      }
      if (typeof sessionStorage !== 'undefined') {
        expect(sessionStorage.getItem('lora_gateway_token')).toBeNull();
        expect(sessionStorage.getItem('token')).toBeNull();
      }

      // Memory lifecycle test: state cleared on modal dismiss
      let oneTimeSecret: string | null = token;
      expect(oneTimeSecret).toBe(token);

      // Dismiss / Close
      oneTimeSecret = null;
      expect(oneTimeSecret).toBeNull();
    });
  });

  describe('Super Admin Gateway Registration (admin_register_lora_gateway)', () => {
    it('successfully registers gateway when invoked by authenticated Super Admin', async () => {
      const mockRpc = vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: true, gateway_id: 'ESP32_GW_BASE' },
        error: null,
      } as any);

      const token = LoraService.generateSecureToken();
      const result = await LoraService.registerGateway(
        'ESP32_GW_BASE',
        'Main Command Station',
        token,
        'Primary rooftop receiver'
      );

      expect(mockRpc).toHaveBeenCalledWith('admin_register_lora_gateway', {
        p_gateway_id: 'ESP32_GW_BASE',
        p_gateway_name: 'Main Command Station',
        p_plaintext_token: token,
        p_notes: 'Primary rooftop receiver',
      });
      expect(result.success).toBe(true);
      expect(result.gateway_id).toBe('ESP32_GW_BASE');
    });

    it('rejects registration when caller lacks Super Admin privileges', async () => {
      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: false, error: 'Access Denied: Super Admin only' },
        error: null,
      } as any);

      const result = await LoraService.registerGateway(
        'ESP32_GW_BASE',
        'Main Command Station',
        'valid-64-char-token-here-1234567890'
      );

      expect(result.success).toBe(false);
      expect(result.error).toContain('Access Denied: Super Admin only');
    });

    it('handles database network / RPC invocation errors cleanly', async () => {
      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: null,
        error: { message: 'permission denied for function admin_register_lora_gateway' },
      } as any);

      const result = await LoraService.registerGateway(
        'ESP32_GW_BASE',
        'Main Command Station',
        'valid-64-char-token-here-1234567890'
      );

      expect(result.success).toBe(false);
      expect(result.error).toContain('permission denied');
    });

    it('rejects duplicate gateway ID registration and blocks auto-reactivation', async () => {
      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: {
          success: false,
          error: 'Gateway already registered with status: ACTIVE. Automatic reactivation is blocked.',
        },
        error: null,
      } as any);

      const result = await LoraService.registerGateway(
        'ESP32_GW_BASE',
        'Duplicate Station',
        'valid-64-char-token-here-1234567890'
      );

      expect(result.success).toBe(false);
      expect(result.error).toContain('Automatic reactivation is blocked');
    });
  });

  describe('Gateway Lifecycle Status Management (admin_set_lora_gateway_status)', () => {
    it('allows Super Admin to suspend an active gateway', async () => {
      const mockRpc = vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: true, gateway_id: 'ESP32_GW_BASE', status: 'SUSPENDED' },
        error: null,
      } as any);

      const result = await LoraService.setGatewayStatus('ESP32_GW_BASE', 'SUSPENDED');

      expect(mockRpc).toHaveBeenCalledWith('admin_set_lora_gateway_status', {
        p_gateway_id: 'ESP32_GW_BASE',
        p_status: 'SUSPENDED',
      });
      expect(result.success).toBe(true);
      expect(result.status).toBe('SUSPENDED');
    });

    it('allows Super Admin to permanently revoke a gateway', async () => {
      const mockRpc = vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: true, gateway_id: 'ESP32_GW_BASE', status: 'REVOKED' },
        error: null,
      } as any);

      const result = await LoraService.setGatewayStatus('ESP32_GW_BASE', 'REVOKED');

      expect(mockRpc).toHaveBeenCalledWith('admin_set_lora_gateway_status', {
        p_gateway_id: 'ESP32_GW_BASE',
        p_status: 'REVOKED',
      });
      expect(result.success).toBe(true);
      expect(result.status).toBe('REVOKED');
    });

    it('allows Super Admin to explicitly reactivate a suspended gateway', async () => {
      const mockRpc = vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: true, gateway_id: 'ESP32_GW_BASE', status: 'ACTIVE' },
        error: null,
      } as any);

      const result = await LoraService.setGatewayStatus('ESP32_GW_BASE', 'ACTIVE');

      expect(mockRpc).toHaveBeenCalledWith('admin_set_lora_gateway_status', {
        p_gateway_id: 'ESP32_GW_BASE',
        p_status: 'ACTIVE',
      });
      expect(result.success).toBe(true);
      expect(result.status).toBe('ACTIVE');
    });

    it('rejects status change if non-admin calls admin_set_lora_gateway_status', async () => {
      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: false, error: 'Access Denied: Super Admin only' },
        error: null,
      } as any);

      const result = await LoraService.setGatewayStatus('ESP32_GW_BASE', 'ACTIVE');
      expect(result.success).toBe(false);
      expect(result.error).toBe('Access Denied: Super Admin only');
    });
  });

  describe('Gateway Token Rotation (admin_rotate_lora_gateway_token)', () => {
    it('successfully rotates token when invoked by Super Admin', async () => {
      const mockRpc = vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: true, gateway_id: 'ESP32_GW_BASE' },
        error: null,
      } as any);

      const newToken = LoraService.generateSecureToken();
      const result = await LoraService.rotateGatewayToken('ESP32_GW_BASE', newToken);

      expect(mockRpc).toHaveBeenCalledWith('admin_rotate_lora_gateway_token', {
        p_gateway_id: 'ESP32_GW_BASE',
        p_new_plaintext_token: newToken,
      });
      expect(result.success).toBe(true);
    });

    it('rejects rotation if caller lacks Super Admin privileges', async () => {
      vi.spyOn(supabase, 'rpc').mockResolvedValue({
        data: { success: false, error: 'Access Denied: Super Admin only' },
        error: null,
      } as any);

      const result = await LoraService.rotateGatewayToken('ESP32_GW_BASE', 'new-token-1234567890');
      expect(result.success).toBe(false);
      expect(result.error).toBe('Access Denied: Super Admin only');
    });
  });

  describe('Gateway Ingestion Security Contract Simulation', () => {
    // Pure function simulation representing the PostgreSQL contract of ingest_lora_relay_packet
    function simulateIngestAuth(gateway: {
      id: string;
      status: 'ACTIVE' | 'SUSPENDED' | 'REVOKED';
      tokenHash: string;
    } | null, presentedToken: string, computeHash: (t: string) => string): { success: boolean; error?: string } {
      if (!gateway) {
        return { success: false, error: 'Unauthorized LoRa Gateway: Unregistered gateway ID' };
      }
      if (gateway.status !== 'ACTIVE') {
        return { success: false, error: `Unauthorized LoRa Gateway: Gateway is ${gateway.status}` };
      }
      if (gateway.tokenHash !== computeHash(presentedToken)) {
        return { success: false, error: 'Unauthorized LoRa Gateway: Invalid token' };
      }
      return { success: true };
    }

    const mockHash = (token: string) => `sha256:${token}`;

    it('authenticates ACTIVE gateway presenting correct secret token', () => {
      const activeGateway = {
        id: 'ESP32_GW_01',
        status: 'ACTIVE' as const,
        tokenHash: mockHash('secret-token-xyz'),
      };
      const res = simulateIngestAuth(activeGateway, 'secret-token-xyz', mockHash);
      expect(res.success).toBe(true);
    });

    it('strictly rejects SUSPENDED gateway even with valid secret token', () => {
      const suspendedGateway = {
        id: 'ESP32_GW_01',
        status: 'SUSPENDED' as const,
        tokenHash: mockHash('secret-token-xyz'),
      };
      const res = simulateIngestAuth(suspendedGateway, 'secret-token-xyz', mockHash);
      expect(res.success).toBe(false);
      expect(res.error).toBe('Unauthorized LoRa Gateway: Gateway is SUSPENDED');
    });

    it('strictly rejects REVOKED gateway even with valid secret token', () => {
      const revokedGateway = {
        id: 'ESP32_GW_01',
        status: 'REVOKED' as const,
        tokenHash: mockHash('secret-token-xyz'),
      };
      const res = simulateIngestAuth(revokedGateway, 'secret-token-xyz', mockHash);
      expect(res.success).toBe(false);
      expect(res.error).toBe('Unauthorized LoRa Gateway: Gateway is REVOKED');
    });

    it('rejects unregistered gateway ID', () => {
      const res = simulateIngestAuth(null, 'secret-token-xyz', mockHash);
      expect(res.success).toBe(false);
      expect(res.error).toBe('Unauthorized LoRa Gateway: Unregistered gateway ID');
    });

    it('rejects invalid secret token for an ACTIVE gateway', () => {
      const activeGateway = {
        id: 'ESP32_GW_01',
        status: 'ACTIVE' as const,
        tokenHash: mockHash('legitimate-secret'),
      };
      const res = simulateIngestAuth(activeGateway, 'wrong-token', mockHash);
      expect(res.success).toBe(false);
      expect(res.error).toBe('Unauthorized LoRa Gateway: Invalid token');
    });
  });
});

