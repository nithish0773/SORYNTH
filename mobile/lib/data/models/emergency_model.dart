import '../../core/constants/app_constants.dart';

class EmergencyModel {
  final String emergencyId; // e.g. SOR100001
  final String personId;
  final String personName;
  final String? phone;
  final double latitude;
  final double longitude;
  final double? accuracy; // GPS accuracy in meters reported by Android
  final EmergencyType emergencyType;
  final String message;
  final CommunicationMethod communicationMethod;
  final EmergencyStatus status;
  final DateTime timestamp; // Original GPS fix timestamp
  final int hopCount;
  final List<String> relayPath;
  final bool isGuest;
  final int retryCount;
  final String? assignedTeam;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final bool wasQueuedOffline;

  const EmergencyModel({
    required this.emergencyId,
    required this.personId,
    required this.personName,
    this.phone,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.emergencyType,
    this.message = 'SOS',
    required this.communicationMethod,
    required this.status,
    required this.timestamp,
    this.hopCount = 0,
    this.relayPath = const [],
    this.isGuest = false,
    this.retryCount = 0,
    this.assignedTeam,
    this.acknowledgedAt,
    this.resolvedAt,
    this.wasQueuedOffline = false,
  });
  bool get hasValidCoordinates =>
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude >= -180.0 &&
      longitude <= 180.0 &&
      (latitude != 0.0 || longitude != 0.0);
  String get coordinatesFormatted => hasValidCoordinates
      ? '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}'
      : 'Location Unavailable';

  bool get isGpsAccurate =>
      hasValidCoordinates && accuracy != null && accuracy! <= 30.0;
  bool get isGpsApproximate =>
      !hasValidCoordinates || accuracy == null || accuracy! > 30.0;
  String get accuracyFormatted => (hasValidCoordinates && accuracy != null)
      ? '±${accuracy!.round()}m'
      : 'Location Unavailable';
  String get accuracyQualityLabel {
    if (!hasValidCoordinates) return 'Location Unavailable';
    if (accuracy == null) return 'Approximate Fix';
    if (isGpsAccurate) return 'Precise GPS Fix (±${accuracy!.round()}m)';
    return 'Approximate Fix (±${accuracy!.round()}m)';
  }

  /// Whether the alert has received verified confirmation from the SORYNTH server
  bool get isServerConfirmed =>
      status == EmergencyStatus.uploadedToServer ||
      status == EmergencyStatus.rescueTeamAcknowledged ||
      status == EmergencyStatus.inAction ||
      status == EmergencyStatus.resolved;

  /// Genuinely active SOS statuses on client device:
  /// Alert is in local acquisition, pending transmission, mesh relaying,
  /// or undergoing active rescue team action (rescueTeamAcknowledged, inAction).
  /// Uploaded (initial server upload complete), resolved, or cancelled alerts are NOT active.
  bool get isGenuinelyActive =>
      status != EmergencyStatus.uploadedToServer &&
      status != EmergencyStatus.resolved &&
      status != EmergencyStatus.cancelled;

  /// High-integrity status label: Only claims server delivery after server confirmation
  String get deliveryStatusLabel {
    if (isServerConfirmed) {
      return 'Server Delivery Confirmed';
    } else if (status == EmergencyStatus.gatewayReceived) {
      return 'LoRa Gateway Received (Server Uplink Pending)';
    } else if (status == EmergencyStatus.relayReceived) {
      return 'Relayed via LoRa Mesh (Server Uplink Pending)';
    } else if (status == EmergencyStatus.transmittingViaLora) {
      return 'Transmitting via LoRa Radio';
    } else if (status == EmergencyStatus.connectingToEsp32) {
      return 'Connecting to Hardware ESP32';
    } else if (status == EmergencyStatus.failed) {
      return 'Transmission Blocked';
    } else if (status == EmergencyStatus.cancelled) {
      return 'Cancelled by Sender';
    } else {
      return 'Queued Locally (Pending Server Delivery)';
    }
  }

  EmergencyModel copyWith({
    String? emergencyId,
    String? personId,
    String? personName,
    String? phone,
    double? latitude,
    double? longitude,
    double? accuracy,
    EmergencyType? emergencyType,
    String? message,
    CommunicationMethod? communicationMethod,
    EmergencyStatus? status,
    DateTime? timestamp,
    int? hopCount,
    List<String>? relayPath,
    bool? isGuest,
    int? retryCount,
    String? assignedTeam,
    DateTime? acknowledgedAt,
    DateTime? resolvedAt,
    bool? wasQueuedOffline,
  }) {
    return EmergencyModel(
      emergencyId: emergencyId ?? this.emergencyId,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      phone: phone ?? this.phone,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      emergencyType: emergencyType ?? this.emergencyType,
      message: message ?? this.message,
      communicationMethod: communicationMethod ?? this.communicationMethod,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      hopCount: hopCount ?? this.hopCount,
      relayPath: relayPath ?? this.relayPath,
      isGuest: isGuest ?? this.isGuest,
      retryCount: retryCount ?? this.retryCount,
      assignedTeam: assignedTeam ?? this.assignedTeam,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      wasQueuedOffline: wasQueuedOffline ?? this.wasQueuedOffline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'emergency_id': emergencyId,
      'emergency_code': emergencyId,
      'person_id': personId,
      'person_name': personName,
      'sender_name': personName,
      'phone': phone,
      'sender_phone': phone,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'accuracy_meters': accuracy,
      'emergency_type': emergencyType.code,
      'message': message,
      'custom_message': message,
      'communication_method': communicationMethod.code,
      'status': status.code,
      'timestamp': timestamp.toIso8601String(),
      'created_at': timestamp.toIso8601String(),
      'hop_count': hopCount,
      'relay_path': relayPath,
      'is_guest': isGuest,
      'retry_count': retryCount,
      'assigned_team': assignedTeam,
      'acknowledged_at': acknowledgedAt?.toIso8601String(),
      'resolved_at': resolvedAt?.toIso8601String(),
      'was_queued_offline': wasQueuedOffline,
    };
  }

  /// Compact payload optimized for LoRa packets over BLE
  Map<String, dynamic> toLoRaPayload() {
    return {
      'id': emergencyId,
      't': emergencyType.code,
      'lat': double.parse(latitude.toStringAsFixed(6)),
      'lng': double.parse(longitude.toStringAsFixed(6)),
      'acc': accuracy?.round() ?? 0,
      'hops': hopCount,
      'ts': timestamp.millisecondsSinceEpoch ~/ 1000,
      'm': message.length > 40 ? message.substring(0, 40) : message,
    };
  }

  factory EmergencyModel.fromJson(Map<String, dynamic> json) {
    return EmergencyModel(
      emergencyId:
          (json['emergency_id'] ?? json['emergency_code'] ?? '').toString(),
      personId:
          (json['person_id'] ?? json['user_id'] ?? 'ANONYMOUS').toString(),
      personName: (json['person_name'] ?? json['sender_name'] ?? 'Guest User')
          .toString(),
      phone: json['phone'] ?? json['sender_phone'],
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      accuracy:
          (json['accuracy'] ?? json['accuracy_meters'] as num?)?.toDouble(),
      emergencyType:
          EmergencyType.fromCode(json['emergency_type']?.toString() ?? 'OTHER'),
      message: (json['message'] ?? json['custom_message'] ?? 'SOS').toString(),
      communicationMethod: CommunicationMethod.fromCode(
        json['communication_method']?.toString() ?? 'INTERNET',
      ),
      status: EmergencyStatus.fromCode(
          json['status']?.toString() ?? 'QUEUED_LOCALLY'),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'].toString()) ??
                  DateTime.now()
              : DateTime.now()),
      hopCount: (json['hop_count'] as num?)?.toInt() ?? 0,
      relayPath: (json['relay_path'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isGuest: json['is_guest'] as bool? ?? false,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      assignedTeam: json['assigned_team']?.toString(),
      acknowledgedAt: json['acknowledged_at'] != null
          ? DateTime.tryParse(json['acknowledged_at'].toString())
          : null,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
      wasQueuedOffline: json['was_queued_offline'] as bool? ??
          (json['status'] == 'QUEUED_LOCALLY' ||
              json['status'] == 'PENDING' ||
              json['status'] == 'STORED'),
    );
  }
}
