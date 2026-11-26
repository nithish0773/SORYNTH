// SORYNTH HARDWARE & TELEMETRY INTERFACES
// Planned Hardware Architecture:
// SOS Sender (ESP32) -> LoRa Relay Node(s) -> LoRa Gateway (ESP32) -> Internet -> Supabase -> Dashboard
// Components: ESP32, LoRa Module, Antenna, LED Display, PCB/Breadboard, USB-C, Jumper Wires

export type TelemetrySource = 'LIVE_HARDWARE' | 'SIMULATED_TEST';

export type HardwareNodeRole = 'GATEWAY' | 'REPEATER_RELAY' | 'SENDER_NODE';

export type HardwareNodeOperationalStatus = 'ONLINE' | 'STANDBY' | 'LOW_BATTERY' | 'OFFLINE' | 'HARDWARE_PENDING';

export interface LoraTelemetryPacket {
  packetId: string;
  emergencyId: string;
  emergencyCode: string;
  nodeId: string;            // ESP32 Transceiver ID / MAC
  gatewayId?: string | null; // Receiving Gateway ID
  senderId?: string | null;  // Original sender device
  hopNumber: number;         // Current hop index
  hopCount: number;          // Total hops traversed
  relayPath?: string[];      // Array of node IDs traversed
  rssi?: number | null;      // Received Signal Strength Indicator in dBm (-145 to 0)
  snr?: number | null;       // Signal to Noise Ratio in dB (-30.0 to +30.0)
  batteryMv?: number | null; // Battery voltage in millivolts (only when hardware supplies)
  batteryPercent?: number | null; // Calculated battery percentage
  payloadRaw?: string | null;// Raw OTA payload frame
  receivedAt: string;        // ISO timestamp of packet reception
  source: TelemetrySource;   // Strict distinction: LIVE_HARDWARE vs SIMULATED_TEST
  isSimulated: boolean;      // True if generated in test bench / simulation mode
}

export interface HardwareNodeStatus {
  nodeId: string;
  role: HardwareNodeRole;
  status: HardwareNodeOperationalStatus;
  lastHeard: string;
  maxHopTraversed: number;
  avgRssi: number | null;
  avgSnr: number | null;
  totalPacketsReceived: number;
  batteryMv?: number | null;
  batteryPercent?: number | null;
  isGateway: boolean;
  source: TelemetrySource;
}

export interface GatewayStatusReport {
  gatewayId: string;
  isConnected: boolean;
  isHardwarePending: boolean;
  lastHeartbeat?: string | null;
  uplinkType: 'WIFI' | 'CELLULAR_LTE' | 'ETHERNET' | 'NONE';
  frequencyMhz: number; // e.g. 868, 915, 433
  activeRelayCount: number;
  totalPacketsProcessed: number;
  source: TelemetrySource;
}

