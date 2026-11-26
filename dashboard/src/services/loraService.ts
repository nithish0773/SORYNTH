import { supabase } from './supabaseClient';
import type { RelayLog, HardwareNodeInfo, LoraGateway } from '../types';

export interface LoraNetworkStatus {
  isHardwarePending: boolean;
  gatewayConnected: boolean;
  totalPackets: number;
  activeNodesCount: number;
  averageRssi: number | null;
  averageSnr: number | null;
  nodes: HardwareNodeInfo[];
  recentLogs: RelayLog[];
}

export class LoraService {
  /**
   * Fetches genuine LoRa relay logs from public.relay_logs
   */
  static async getRelayLogs(limit = 100): Promise<RelayLog[]> {
    try {
      const { data, error } = await supabase
        .from('relay_logs')
        .select('*')
        .order('received_at', { ascending: false })
        .limit(limit);

      if (error) {
        console.warn('Relay logs query:', error.message);
        return [];
      }

      return (data as RelayLog[]) || [];
    } catch (err) {
      console.error('Failed to get relay logs:', err);
      return [];
    }
  }

  /**
   * Analyzes actual relay logs to determine hardware status.
   * If no real hardware logs exist, returns status with isHardwarePending: true.
   * Never shows fake ONLINE status.
   */
  static analyzeNetworkState(logs: RelayLog[]): LoraNetworkStatus {
    if (!logs || logs.length === 0) {
      return {
        isHardwarePending: true,
        gatewayConnected: false,
        totalPackets: 0,
        activeNodesCount: 0,
        averageRssi: null,
        averageSnr: null,
        nodes: [],
        recentLogs: [],
      };
    }

    const nodeMap = new Map<string, {
      nodeId: string;
      lastSeen: string;
      maxHop: number;
      rssiSum: number;
      snrSum: number;
      count: number;
      isGateway: boolean;
    }>();

    let totalRssi = 0;
    let rssiCount = 0;
    let totalSnr = 0;
    let snrCount = 0;

    const now = Date.now();
    // Gateway is considered active if packet received in last 15 minutes
    let gatewayActive = false;

    for (const log of logs) {
      const nodeKey = log.node_id;
      const logTime = new Date(log.received_at).getTime();
      const isRecent = (now - logTime) < 15 * 60 * 1000;

      if (log.gateway_id) {
        if (isRecent) gatewayActive = true;
      }

      if (log.rssi !== null && log.rssi !== undefined) {
        totalRssi += log.rssi;
        rssiCount++;
      }
      if (log.snr !== null && log.snr !== undefined) {
        totalSnr += log.snr;
        snrCount++;
      }

      const existing = nodeMap.get(nodeKey);
      if (!existing) {
        nodeMap.set(nodeKey, {
          nodeId: log.node_id,
          lastSeen: log.received_at,
          maxHop: log.hop_number,
          rssiSum: log.rssi ?? 0,
          snrSum: log.snr ?? 0,
          count: 1,
          isGateway: Boolean(log.gateway_id && log.gateway_id === log.node_id),
        });
      } else {
        existing.count++;
        if (new Date(log.received_at) > new Date(existing.lastSeen)) {
          existing.lastSeen = log.received_at;
        }
        if (log.hop_number > existing.maxHop) existing.maxHop = log.hop_number;
        if (log.rssi) existing.rssiSum += log.rssi;
        if (log.snr) existing.snrSum += log.snr;
      }
    }

    const nodes: HardwareNodeInfo[] = Array.from(nodeMap.values()).map(n => {
      const timeDiff = now - new Date(n.lastSeen).getTime();
      // Only show ONLINE if heartbeat was within last 15 minutes
      const isOnline = timeDiff < 15 * 60 * 1000;

      return {
        nodeId: n.nodeId,
        lastSeen: n.lastSeen,
        hopCount: n.maxHop,
        avgRssi: n.count > 0 ? Math.round(n.rssiSum / n.count) : -100,
        avgSnr: n.count > 0 ? Math.round((n.snrSum / n.count) * 10) / 10 : 0,
        totalPackets: n.count,
        status: isOnline ? 'ONLINE' : 'OFFLINE',
        isGateway: n.isGateway,
      };
    });

    return {
      isHardwarePending: false,
      gatewayConnected: gatewayActive,
      totalPackets: logs.length,
      activeNodesCount: nodes.filter(n => n.status === 'ONLINE').length,
      averageRssi: rssiCount > 0 ? Math.round(totalRssi / rssiCount) : null,
      averageSnr: snrCount > 0 ? Math.round((totalSnr / snrCount) * 10) / 10 : null,
      nodes,
      recentLogs: logs,
    };
  }

  /**
   * Subscribes to real-time LoRa relay logs
   */
  static subscribeToRelayLogs(onLog: (log: RelayLog) => void) {
    const channel = supabase
      .channel('command_relay_logs_realtime')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'relay_logs' },
        (payload) => onLog(payload.new as RelayLog)
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }

  /**
   * Generates a 256-bit cryptographically secure random hexadecimal token for ESP32 gateway provisioning.
   * Leverages hardware CSPRNG (globalThis.crypto.getRandomValues).
   */
  static generateSecureToken(): string {
    const bytes = new Uint8Array(32);
    globalThis.crypto.getRandomValues(bytes);
    return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  }

  /**
   * Registers a new physical LoRa Gateway in public.lora_gateways.
   * Requires authenticated Super Admin session (auth.uid()).
   * Plaintext token is hashed via SHA-256 inside PostgreSQL and never stored in plaintext.
   */
  static async registerGateway(
    gatewayId: string,
    gatewayName: string,
    plaintextToken: string,
    notes?: string
  ): Promise<{ success: boolean; gateway_id?: string; error?: string }> {
    try {
      const { data, error } = await supabase.rpc('admin_register_lora_gateway', {
        p_gateway_id: gatewayId,
        p_gateway_name: gatewayName,
        p_plaintext_token: plaintextToken,
        p_notes: notes || null,
      });

      if (error) {
        return { success: false, error: error.message };
      }

      return (data as { success: boolean; gateway_id?: string; error?: string }) || { success: false, error: 'Empty response' };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown gateway registration error';
      return { success: false, error: msg };
    }
  }

  /**
   * Updates an existing gateway's lifecycle status (ACTIVE, SUSPENDED, REVOKED).
   * Requires authenticated Super Admin session.
   */
  static async setGatewayStatus(
    gatewayId: string,
    status: 'ACTIVE' | 'SUSPENDED' | 'REVOKED'
  ): Promise<{ success: boolean; status?: string; error?: string }> {
    try {
      const { data, error } = await supabase.rpc('admin_set_lora_gateway_status', {
        p_gateway_id: gatewayId,
        p_status: status,
      });

      if (error) {
        return { success: false, error: error.message };
      }

      return (data as { success: boolean; status?: string; error?: string }) || { success: false, error: 'Empty response' };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown gateway status error';
      return { success: false, error: msg };
    }
  }

  /**
   * Rotates a gateway's token to a newly generated secure token.
   * Requires authenticated Super Admin session.
   */
  static async rotateGatewayToken(
    gatewayId: string,
    newPlaintextToken: string
  ): Promise<{ success: boolean; gateway_id?: string; error?: string }> {
    try {
      const { data, error } = await supabase.rpc('admin_rotate_lora_gateway_token', {
        p_gateway_id: gatewayId,
        p_new_plaintext_token: newPlaintextToken,
      });

      if (error) {
        return { success: false, error: error.message };
      }

      return (data as { success: boolean; gateway_id?: string; error?: string }) || { success: false, error: 'Empty response' };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown token rotation error';
      return { success: false, error: msg };
    }
  }

  /**
   * Fetches registered physical LoRa gateways from public.lora_gateways.
   * Accessible by authenticated Super Admins via RLS.
   * Note: token_hash is excluded from SELECT for security.
   */
  static async getRegisteredGateways(): Promise<LoraGateway[]> {
    try {
      const { data, error } = await supabase
        .from('lora_gateways')
        .select('gateway_id, gateway_name, status, created_at, last_seen_at, registered_by, notes')
        .order('created_at', { ascending: false });

      if (error) {
        console.warn('Failed to fetch registered gateways:', error.message);
        return [];
      }

      return (data as LoraGateway[]) || [];
    } catch (err: unknown) {
      console.error('Error fetching registered gateways:', err);
      return [];
    }
  }
}

