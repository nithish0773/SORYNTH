// SORYNTH RESCUE COMMAND DASHBOARD - TYPE DEFINITIONS
// Project: Hybrid Internet and LoRa-Based Emergency SOS Communication System

export type EmergencyType =
  | 'MEDICAL'
  | 'ACCIDENT'
  | 'FIRE'
  | 'NATURAL_DISASTER'
  | 'LOST_STRANDED'
  | 'OTHER';

export type CommunicationMethod =
  | 'INTERNET'
  | 'BLUETOOTH_LORA'
  | 'LORA_RELAY'
  | 'HYBRID';

export type EmergencyStatus =
  | 'PENDING'
  | 'STORED'
  | 'TRANSMITTING'
  | 'RELAYED'
  | 'DELIVERED'
  | 'ACKNOWLEDGED'
  | 'IN_ACTION'
  | 'RESOLVED'
  | 'CANCELLED'
  | 'FAILED';

// UI Friendly Status Groups (Mapping backend statuses to dashboard workflow)
export type UiEmergencyStatus =
  | 'RECEIVED'       // DELIVERED, STORED, TRANSMITTING, PENDING, RELAYED
  | 'ACKNOWLEDGED'   // ACKNOWLEDGED
  | 'RESPONDING'      // IN_ACTION
  | 'RESOLVED'       // RESOLVED
  | 'CANCELLED';     // CANCELLED, FAILED

export type SystemRole = 'SUPER_ADMIN' | 'RESCUE_OPERATOR';

export type AccountStatus = 'ACTIVE' | 'INACTIVE';

export type RescueRole =
  | 'COMMANDER'
  | 'PARAMEDIC'
  | 'SEARCH_AND_RESCUE'
  | 'DISPATCHER'
  | 'VOLUNTEER';

export type RescueTeamStatus = 'ACTIVE' | 'ON_MISSION' | 'STANDBY';

export interface RescueTeam {
  id: string;
  team_name: string;
  jurisdiction_zone: string;
  contact_phone: string;
  status: RescueTeamStatus;
  latitude?: number | null;
  longitude?: number | null;
  created_at: string;
}

export interface Emergency {
  id: string;
  emergency_code: string; // e.g. SOR100001
  user_id?: string | null;
  is_guest: boolean;
  sender_name?: string | null;
  sender_phone?: string | null;
  emergency_type: EmergencyType;
  custom_message?: string | null;
  latitude: number;
  longitude: number;
  accuracy_meters?: number | null;
  altitude?: number | null;
  communication_method: CommunicationMethod;
  status: EmergencyStatus;
  hop_count: number;
  relay_path?: string[] | null;
  assigned_team_id?: string | null;
  assigned_team?: RescueTeam | null;
  created_at: string;
  acknowledged_at?: string | null;
  resolved_at?: string | null;
  updated_at: string;
}

export interface EmergencyUpdate {
  id: string;
  emergency_id: string;
  previous_status?: EmergencyStatus | null;
  new_status: EmergencyStatus;
  note?: string | null;
  updated_by_user_id?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  created_at: string;
}

export interface RelayLog {
  id: string;
  emergency_id: string;
  node_id: string; // ESP32 device ID / MAC
  gateway_id?: string | null;
  rssi?: number | null; // dBm (-120 to -30)
  snr?: number | null; // Signal-to-noise ratio
  hop_number: number;
  payload_raw?: string | null;
  received_at: string;
}

export interface UserProfile {
  id: string;
  full_name: string;
  phone_number?: string | null;
  email?: string | null;
  blood_group?: string | null;
  medical_notes?: string | null;
  emergency_contact_name?: string | null;
  emergency_contact_phone?: string | null;
  rescue_role?: RescueRole | null;
  system_role: SystemRole;
  employee_id?: string | null;
  status: AccountStatus;
  is_active: boolean;
  jurisdiction_zone?: string | null;
  assigned_team_id?: string | null;
  last_login_at?: string | null;
  must_change_password?: boolean | null;
  created_at: string;
  updated_at: string;
}

export type AuditAction = 
  | 'OPERATOR_CREATED'
  | 'OPERATOR_ACTIVATED'
  | 'OPERATOR_DEACTIVATED'
  | 'OPERATOR_UPDATED'
  | 'OPERATOR_PASSWORD_RESET'
  | 'OPERATOR_DELETED'
  | 'SOS_ACCEPTED'
  | 'EMERGENCY_ASSIGNED'
  | 'STATUS_CHANGED'
  | 'EMERGENCY_RESOLVED'
  | 'LOGIN'
  | 'LOGOUT'
  | 'PASSWORD_CHANGED';

export interface AuditLog {
  id: string;
  actor_id?: string | null;
  actor_email?: string | null;
  actor_name?: string | null;
  actor_role?: string | null;
  action: AuditAction | string;
  entity_type?: string | null;
  entity_id?: string | null;
  details?: Record<string, unknown> | null;
  ip_address?: string | null;
  created_at: string;
}

export interface OperatorCreationPayload {
  full_name: string;
  email: string;
  phone_number?: string;
  rescue_role: RescueRole;
  jurisdiction_zone: string;
  status: AccountStatus;
  employee_id?: string;
  initial_password?: string;
  must_change_password?: boolean;
}

export interface KpiStats {
  activeEmergencies: number;
  totalEmergencies: number;
  resolvedEmergencies: number;
  availableRescueTeams: number;
  verifiedRelayNodes: number;
  averageResponseTimeMinutes: number;
}

export interface EmergencyFilterOptions {
  searchQuery: string;
  status: string; // 'ALL' or specific status
  emergencyType: string; // 'ALL' or specific type
  communicationMethod: string; // 'ALL' or specific method
  isGuest: string; // 'ALL' | 'GUEST' | 'REGISTERED'
  sortBy: 'created_at_desc' | 'created_at_asc' | 'status' | 'type';
}

export interface HardwareNodeInfo {
  nodeId: string;
  lastSeen: string;
  hopCount: number;
  avgRssi: number;
  avgSnr: number;
  totalPackets: number;
  status: 'ONLINE' | 'OFFLINE' | 'HARDWARE_PENDING';
  isGateway: boolean;
}

export type GatewayStatus = 'ACTIVE' | 'SUSPENDED' | 'REVOKED';

export interface LoraGateway {
  gateway_id: string;
  gateway_name: string;
  status: GatewayStatus;
  created_at: string;
  last_seen_at?: string | null;
  registered_by?: string | null;
  notes?: string | null;
}

