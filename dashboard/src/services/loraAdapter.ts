import type { RelayLog, HardwareNodeInfo } from '../types';
import type { 
  LoraTelemetryPacket, 
  GatewayStatusReport, 
  TelemetrySource 
} from '../types/hardware';

/**
 * Modular LoRa Gateway & Hardware Adapter
 * Evaluates 100% genuine hardware telemetry and relay logs from the Supabase database.
 * No synthetic or simulated packets.
 */
export class LoraAdapter {
  /**
   * Converts a real database relay_log row into a normalized LoraTelemetryPacket
   */
  static convertRelayLogToPacket(log: RelayLog, emergencyCode?: string): LoraTelemetryPacket {
    return {
      packetId: log.id,
      emergencyId: log.emergency_id,
      emergencyCode: emergencyCode || 'SOR-RECORD',
      nodeId: log.node_id,
      gatewayId: log.gateway_id || null,
      hopNumber: log.hop_number,
      hopCount: log.hop_number,
      rssi: log.rssi ?? null,
      snr: log.snr ?? null,
      batteryMv: null,
      batteryPercent: null,
      payloadRaw: log.payload_raw || null,
      receivedAt: log.received_at,
      source: 'LIVE_HARDWARE',
      isSimulated: false,
    };
  }

  /**
   * Evaluates telemetry physical radio bounds (sanity check)
   */
  static validateRfSanity(rssi?: number | null, snr?: number | null, hop?: number): boolean {
    if (rssi !== null && rssi !== undefined && (rssi < -145 || rssi > 0)) return false;
    if (snr !== null && snr !== undefined && (snr < -30.0 || snr > 30.0)) return false;
    if (hop !== null && hop !== undefined && (hop < 1 || hop > 16)) return false;
    return true;
  }

  /**
   * Evaluates genuine database relay_logs from Supabase.
   * Reports genuine gateway connectivity and active repeater nodes.
   */
  static analyze(
    liveLogs: RelayLog[] = []
  ): {
    isHardwarePending: boolean;
    gatewayConnected: boolean;
    totalPackets: number;
    activeNodesCount: number;
    averageRssi: number | null;
    averageSnr: number | null;
    nodes: HardwareNodeInfo[];
    gatewayReport: GatewayStatusReport;
    telemetrySource: TelemetrySource;
    telemetryPackets: LoraTelemetryPacket[];
  } {
    if (!liveLogs || liveLogs.length === 0) {
      return {
        isHardwarePending: true,
        gatewayConnected: false,
        totalPackets: 0,
        activeNodesCount: 0,
        averageRssi: null,
        averageSnr: null,
        nodes: [],
        gatewayReport: {
          gatewayId: 'AWAITING_HARDWARE',
          isConnected: false,
          isHardwarePending: true,
          lastHeartbeat: null,
          uplinkType: 'NONE',
          frequencyMhz: 868,
          activeRelayCount: 0,
          totalPacketsProcessed: 0,
          source: 'LIVE_HARDWARE',
        },
        telemetrySource: 'LIVE_HARDWARE',
        telemetryPackets: [],
      };
    }

    // Process genuine database relay logs
    const livePackets = liveLogs.map(log => this.convertRelayLogToPacket(log));
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
    let gatewayActive = false;

    for (const log of liveLogs) {
      const nodeKey = log.node_id;
      const logTime = new Date(log.received_at).getTime();
      const isRecent = (now - logTime) < 15 * 60 * 1000;

      if (log.gateway_id && isRecent) {
        gatewayActive = true;
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
      totalPackets: liveLogs.length,
      activeNodesCount: nodes.filter(n => n.status === 'ONLINE').length,
      averageRssi: rssiCount > 0 ? Math.round(totalRssi / rssiCount) : null,
      averageSnr: snrCount > 0 ? Math.round((totalSnr / snrCount) * 10) / 10 : null,
      nodes,
      gatewayReport: {
        gatewayId: liveLogs[0]?.gateway_id || 'ESP32_GATEWAY_DETECTED',
        isConnected: gatewayActive,
        isHardwarePending: false,
        lastHeartbeat: liveLogs[0]?.received_at || null,
        uplinkType: 'WIFI',
        frequencyMhz: 868,
        activeRelayCount: Math.max(0, nodes.length - 1),
        totalPacketsProcessed: liveLogs.length,
        source: 'LIVE_HARDWARE',
      },
      telemetrySource: 'LIVE_HARDWARE',
      telemetryPackets: livePackets,
    };
  }
}
