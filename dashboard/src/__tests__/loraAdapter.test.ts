import { describe, it, expect } from 'vitest';
import { LoraAdapter } from '../services/loraAdapter';
import { LoraService } from '../services/loraService';
import type { RelayLog } from '../types';

describe('LoraAdapter - Modular LoRa Hardware Interface & Genuine Telemetry', () => {
  describe('Live Hardware Mode (Awaiting Gateway)', () => {
    it('reports isHardwarePending: true when no physical gateway has reported telemetry', () => {
      const emptyLogs: RelayLog[] = [];
      const result = LoraAdapter.analyze(emptyLogs);

      expect(result.isHardwarePending).toBe(true);
      expect(result.gatewayConnected).toBe(false);
      expect(result.totalPackets).toBe(0);
      expect(result.nodes).toHaveLength(0);
      expect(result.telemetrySource).toBe('LIVE_HARDWARE');
      expect(result.gatewayReport.isConnected).toBe(false);
      expect(result.gatewayReport.gatewayId).toBe('AWAITING_HARDWARE');
    });

    it('correctly parses genuine hardware relay_logs without fabricating fake nodes', () => {
      const realLogs: RelayLog[] = [
        {
          id: 'log-001',
          emergency_id: 'emg-101',
          node_id: 'ESP32_RELAY_01',
          gateway_id: 'ESP32_GW_ALPHA',
          rssi: -75,
          snr: 8.5,
          hop_number: 1,
          payload_raw: '0x01AAFF',
          received_at: new Date().toISOString(),
        },
        {
          id: 'log-002',
          emergency_id: 'emg-101',
          node_id: 'ESP32_RELAY_02',
          gateway_id: 'ESP32_GW_ALPHA',
          rssi: -85,
          snr: 6.0,
          hop_number: 2,
          payload_raw: '0x02AAFF',
          received_at: new Date().toISOString(),
        },
      ];

      const result = LoraAdapter.analyze(realLogs);

      expect(result.isHardwarePending).toBe(false);
      expect(result.totalPackets).toBe(2);
      expect(result.nodes).toHaveLength(2);
      expect(result.averageRssi).toBe(-80); // (-75 + -85) / 2
      expect(result.averageSnr).toBe(7.3);  // (8.5 + 6.0) / 2
      expect(result.telemetrySource).toBe('LIVE_HARDWARE');
      expect(result.telemetryPackets[0].isSimulated).toBe(false);
    });

    it('guarantees that all converted relay logs are marked as genuine LIVE_HARDWARE', () => {
      const log: RelayLog = {
        id: 'log-999',
        emergency_id: 'emg-999',
        node_id: 'ESP32_FIELD_NODE',
        gateway_id: 'ESP32_GW_BASE',
        rssi: -68,
        snr: 10.2,
        hop_number: 1,
        payload_raw: '0x99AABB',
        received_at: new Date().toISOString(),
      };

      const packet = LoraAdapter.convertRelayLogToPacket(log);
      expect(packet.source).toBe('LIVE_HARDWARE');
      expect(packet.isSimulated).toBe(false);
      expect(packet.nodeId).toBe('ESP32_FIELD_NODE');
    });
  });

  describe('RF Sanity Validation', () => {
    it('accepts legitimate RF signal parameters', () => {
      expect(LoraAdapter.validateRfSanity(-85, 8.5, 2)).toBe(true);
      expect(LoraAdapter.validateRfSanity(-120, -5.0, 4)).toBe(true);
      expect(LoraAdapter.validateRfSanity(-45, 12.0, 1)).toBe(true);
    });

    it('rejects physically impossible RF parameters', () => {
      // Impossible RSSI (> 0 dBm or < -145 dBm)
      expect(LoraAdapter.validateRfSanity(10, 5, 1)).toBe(false);
      expect(LoraAdapter.validateRfSanity(-180, 5, 1)).toBe(false);

      // Impossible SNR (> +30 dB or < -30 dB)
      expect(LoraAdapter.validateRfSanity(-80, 50.0, 1)).toBe(false);
      expect(LoraAdapter.validateRfSanity(-80, -40.0, 1)).toBe(false);

      // Impossible hop count (< 1 or > 16)
      expect(LoraAdapter.validateRfSanity(-80, 5, 0)).toBe(false);
      expect(LoraAdapter.validateRfSanity(-80, 5, 25)).toBe(false);
    });
  });

  describe('Secure Gateway Provisioning Utilities', () => {
    it('generates a 256-bit (64 hex characters) cryptographically random token', () => {
      const token1 = LoraService.generateSecureToken();
      const token2 = LoraService.generateSecureToken();

      expect(token1).toHaveLength(64);
      expect(token2).toHaveLength(64);
      expect(token1).toMatch(/^[0-9a-f]{64}$/);
      expect(token2).toMatch(/^[0-9a-f]{64}$/);
      expect(token1).not.toBe(token2); // Must be uniquely randomized
    });
  });
});
