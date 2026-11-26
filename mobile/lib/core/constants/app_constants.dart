import '../config/supabase_credentials.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'SORYNTH';
  static const String appTagline = 'SIGNAL BEYOND BOUNDARIES';
  static const String projectTitle =
      'Hybrid Internet and LoRa-Based Emergency SOS Communication System';

  // Local Storage Keys
  static const String keyOnboardingComplete = 'sorynth_onboarding_completed';
  static const String keyPendingEmergencies = 'sorynth_pending_emergencies_v1';
  static const String keyActiveEmergencyId = 'sorynth_active_emergency_id';
  static const String keyUserSession = 'sorynth_user_session';
  static const String keyGuestId = 'sorynth_guest_id_v1';

  // Bluetooth Low Energy Constants for ESP32
  static const String esp32ServiceUuid =
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String esp32TxCharUuid =
      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String esp32RxCharUuid =
      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
  static const String esp32DevicePrefix = 'SORYNTH';

  // LoRa Configuration Specs
  static const int maxLoRaHops = 5;
  static const int defaultTimeoutSeconds = 15;
  static const int maxRetryAttempts = 3;

  // Supabase Configuration
  static const String defaultSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pmkwudzlyvaegwmugmoy.supabase.co',
  );
  static const String defaultSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: SupabaseCredentials.publishableKey,
  );
}

enum EmergencyType {
  medical(
    label: 'Medical Emergency',
    code: 'MEDICAL',
    description: 'Cardiac arrest, trauma, unconsciousness, severe hemorrhage',
  ),
  accident(
    label: 'Accident',
    code: 'ACCIDENT',
    description: 'Road crash, structural collapse, falls from height',
  ),
  fire(
    label: 'Fire',
    code: 'FIRE',
    description: 'Building fire, forest fire, electrical explosion',
  ),
  naturalDisaster(
    label: 'Natural Disaster',
    code: 'NATURAL_DISASTER',
    description: 'Flood, earthquake, landslide, cyclone',
  ),
  lostStranded(
    label: 'Lost / Stranded',
    code: 'LOST_STRANDED',
    description: 'Isolated in remote terrain, maritime distress, no route',
  ),
  other(
    label: 'Other Urgent Threat',
    code: 'OTHER',
    description: 'Immediate threat to human life requiring rescue dispatch',
  );

  final String label;
  final String code;
  final String description;

  const EmergencyType({
    required this.label,
    required this.code,
    required this.description,
  });

  static EmergencyType fromCode(String code) {
    return EmergencyType.values.firstWhere(
      (e) => e.code.toUpperCase() == code.toUpperCase(),
      orElse: () => EmergencyType.other,
    );
  }
}

enum CommunicationMethod {
  internet('INTERNET', 'Cellular / Wi-Fi Cloud Direct'),
  bluetoothLora('BLUETOOTH_LORA', 'ESP32 BLE Direct Transceiver'),
  loraRelay('LORA_RELAY', 'Mesh Forwarding via Multi-Hop Relays'),
  hybrid('HYBRID', 'Automatic Dual-Mode Failover');

  final String code;
  final String displayName;

  const CommunicationMethod(this.code, this.displayName);

  static CommunicationMethod fromCode(String code) {
    return CommunicationMethod.values.firstWhere(
      (m) => m.code.toUpperCase() == code.toUpperCase(),
      orElse: () => CommunicationMethod.internet,
    );
  }
}

enum EmergencyStatus {
  gpsAcquiring('GPS_ACQUIRING', 'Acquiring GPS Fix', 0),
  gpsLocked('GPS_LOCKED', 'GPS Fix Locked', 1),
  queuedLocally('QUEUED_LOCALLY', 'Queued Locally (Pending Hardware / Network)', 2),
  connectingToEsp32('CONNECTING_TO_ESP32', 'Connecting to ESP32', 3),
  transmittingViaLora('TRANSMITTING_VIA_LORA', 'Transmitting via LoRa', 4),
  relayReceived('RELAY_RECEIVED', 'Relay Received (Multi-Hop)', 5),
  gatewayReceived('GATEWAY_RECEIVED', 'Gateway Received', 6),
  uploadedToServer('UPLOADED_TO_SERVER', 'Uploaded to SORYNTH Server', 7),
  rescueTeamAcknowledged('RESCUE_TEAM_ACKNOWLEDGED', 'Rescue Team Acknowledged', 8),
  inAction('IN_ACTION', 'Rescue Team in Action', 9),
  resolved('RESOLVED', 'Mission Resolved', 10),
  cancelled('CANCELLED', 'Cancelled by Sender', 11),
  failed('FAILED', 'Transmission Blocked', 12);

  final String code;
  final String title;
  final int stageIndex;

  const EmergencyStatus(this.code, this.title, this.stageIndex);

  // Backward compatibility aliases for existing references
  static const EmergencyStatus pending = EmergencyStatus.queuedLocally;
  static const EmergencyStatus stored = EmergencyStatus.queuedLocally;
  static const EmergencyStatus transmitting = EmergencyStatus.transmittingViaLora;
  static const EmergencyStatus relayed = EmergencyStatus.relayReceived;
  static const EmergencyStatus delivered = EmergencyStatus.uploadedToServer;
  static const EmergencyStatus acknowledged = EmergencyStatus.rescueTeamAcknowledged;

  static EmergencyStatus fromCode(String code) {
    final normalized = code.toUpperCase().trim();
    switch (normalized) {
      case 'GPS_ACQUIRING':
        return EmergencyStatus.gpsAcquiring;
      case 'GPS_LOCKED':
        return EmergencyStatus.gpsLocked;
      case 'PENDING':
      case 'STORED':
      case 'QUEUED_LOCALLY':
        return EmergencyStatus.queuedLocally;
      case 'CONNECTING_TO_ESP32':
        return EmergencyStatus.connectingToEsp32;
      case 'TRANSMITTING':
      case 'TRANSMITTING_VIA_LORA':
        return EmergencyStatus.transmittingViaLora;
      case 'RELAYED':
      case 'RELAY_RECEIVED':
        return EmergencyStatus.relayReceived;
      case 'GATEWAY_RECEIVED':
        return EmergencyStatus.gatewayReceived;
      case 'DELIVERED':
      case 'UPLOADED_TO_SERVER':
        return EmergencyStatus.uploadedToServer;
      case 'ACKNOWLEDGED':
      case 'RESCUE_TEAM_ACKNOWLEDGED':
        return EmergencyStatus.rescueTeamAcknowledged;
      case 'IN_ACTION':
        return EmergencyStatus.inAction;
      case 'RESOLVED':
        return EmergencyStatus.resolved;
      case 'CANCELLED':
        return EmergencyStatus.cancelled;
      case 'FAILED':
        return EmergencyStatus.failed;
      default:
        return EmergencyStatus.queuedLocally;
    }
  }
}
