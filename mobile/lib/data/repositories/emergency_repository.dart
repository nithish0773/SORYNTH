import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/emergency_model.dart';
import '../services/bluetooth_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_storage_service.dart';
import '../services/supabase_service.dart';

class SosTransmissionStep {
  final int stepNumber;
  final String title;
  final String detail;
  final bool isCompleted;
  final bool isInProgress;
  final bool isFailed;

  const SosTransmissionStep({
    required this.stepNumber,
    required this.title,
    required this.detail,
    this.isCompleted = false,
    this.isInProgress = false,
    this.isFailed = false,
  });

  SosTransmissionStep copyWith({
    bool? isCompleted,
    bool? isInProgress,
    bool? isFailed,
    String? detail,
  }) {
    return SosTransmissionStep(
      stepNumber: stepNumber,
      title: title,
      detail: detail ?? this.detail,
      isCompleted: isCompleted ?? this.isCompleted,
      isInProgress: isInProgress ?? this.isInProgress,
      isFailed: isFailed ?? this.isFailed,
    );
  }
}

class EmergencyRepository {
  final SupabaseService _supabaseService;
  final BluetoothService _bluetoothService;
  final ConnectivityService _connectivityService;
  final OfflineStorageService _storageService;
  final _emergencyUpdatesController =
      StreamController<EmergencyModel>.broadcast();
  bool _isSyncing = false;

  Stream<EmergencyModel> get emergencyUpdatesStream =>
      _emergencyUpdatesController.stream;

  void _notifyEmergencyUpdated(EmergencyModel updated) {
    if (!_emergencyUpdatesController.isClosed) {
      _emergencyUpdatesController.add(updated);
    }
  }

  EmergencyRepository({
    required SupabaseService supabaseService,
    required BluetoothService bluetoothService,
    required ConnectivityService connectivityService,
    required OfflineStorageService storageService,
  })  : _supabaseService = supabaseService,
        _bluetoothService = bluetoothService,
        _connectivityService = connectivityService,
        _storageService = storageService {
    // Sync when internet becomes available.
    _connectivityService.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        syncPendingEmergencies();
      }
    });

    // Also check internet immediately when repository is created.
    unawaited(_syncPendingEmergenciesAtStartup());
  }

  Future<void> _syncPendingEmergenciesAtStartup() async {
    final isOnline =
        await _connectivityService.checkActualInternetReachability();

    if (isOnline) {
      await syncPendingEmergencies();
    }
  }

  /// Validates whether the Supabase response explicitly confirms delivery.
  ///
  /// Criteria for confirmed acknowledgement:
  /// 1. Response must be a [Map].
  /// 2. Must explicitly contain `success == true` (boolean true).
  /// 3. Must NOT contain error payloads or failure status indicators.
  /// 4. The mere presence of `emergency_id` or `emergency_code` is NEVER
  ///    accepted as proof of delivery without explicit `success == true`.
  static bool isServerAcknowledgementConfirmed(dynamic response) {
    if (response is! Map) return false;
    final map = Map<String, dynamic>.from(response);

    // 1. Explicit boolean confirmation
    if (map['success'] != true) {
      return false;
    }

    // 2. Reject error payloads even if success flag is malformed/inconsistent
    if (map.containsKey('error') && map['error'] != null) {
      return false;
    }

    // 3. Reject failure status indicators
    final status = map['status']?.toString().toUpperCase();
    if (status == 'FAILED' || status == 'ERROR' || status == 'CANCELLED') {
      return false;
    }

    return true;
  }

  /// Generates the accurate 6-stage telemetry steps for an emergency based on its current state and offline history.
  List<SosTransmissionStep> getPipelineSteps(EmergencyModel emergency) {
    final bool hasValidCoords = emergency.hasValidCoordinates;
    final String gpsDetail = hasValidCoords
        ? (emergency.accuracy != null
            ? 'Lat: ${emergency.latitude.toStringAsFixed(4)}, Lng: ${emergency.longitude.toStringAsFixed(4)} (${emergency.accuracyQualityLabel})'
            : 'Lat: ${emergency.latitude.toStringAsFixed(4)}, Lng: ${emergency.longitude.toStringAsFixed(4)} (Approximate)')
        : 'Location unavailable (No GPS satellite fix acquired)';

    if (emergency.isServerConfirmed) {
      if (emergency.wasQueuedOffline) {
        return [
          SosTransmissionStep(
            stepNumber: 1,
            title: 'Capturing GPS Fix',
            detail: gpsDetail,
            isCompleted: true,
          ),
          SosTransmissionStep(
            stepNumber: 2,
            title: 'Preparing Emergency Payload',
            detail: 'ID: ${emergency.emergencyId} • Cached in local offline storage',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 3,
            title: 'Analyzing Network Connectivity',
            detail: 'Internet connection available • Restored after initial offline queue',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 4,
            title: 'Internet Transmission',
            detail: 'Internet transmission successful • Server acknowledgement received from SORYNTH Rescue Network',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 5,
            title: 'Hardware LoRa Failover',
            detail: 'Offline queue resolved: Successfully uploaded via cloud uplink when internet returned',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 6,
            title: 'LoRa Mesh Relay Propagation',
            detail: 'Server acknowledgement confirmed • Direct cloud uplink verified',
            isCompleted: true,
          ),
        ];
      } else {
        return [
          SosTransmissionStep(
            stepNumber: 1,
            title: 'Capturing GPS Fix',
            detail: gpsDetail,
            isCompleted: true,
          ),
          SosTransmissionStep(
            stepNumber: 2,
            title: 'Preparing Emergency Payload',
            detail: 'ID: ${emergency.emergencyId} • Cached in local offline storage',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 3,
            title: 'Analyzing Network Connectivity',
            detail: 'Internet connection verified (Active)',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 4,
            title: 'Internet Transmission',
            detail: 'SOS successfully registered on SORYNTH Rescue Network (Server Delivery Confirmed)',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 5,
            title: 'Hardware LoRa Failover',
            detail: 'Standby • Direct cloud uplink active (Hardware failover not required)',
            isCompleted: true,
          ),
          const SosTransmissionStep(
            stepNumber: 6,
            title: 'LoRa Mesh Relay Propagation',
            detail: 'Standby • Direct cloud uplink active',
            isCompleted: true,
          ),
        ];
      }
    }

    if (emergency.status == EmergencyStatus.gatewayReceived ||
        emergency.status == EmergencyStatus.relayReceived ||
        emergency.status == EmergencyStatus.transmittingViaLora) {
      return [
        SosTransmissionStep(
          stepNumber: 1,
          title: 'Capturing GPS Fix',
          detail: gpsDetail,
          isCompleted: true,
        ),
        SosTransmissionStep(
          stepNumber: 2,
          title: 'Preparing Emergency Payload',
          detail: 'ID: ${emergency.emergencyId} • Cached in local offline storage',
          isCompleted: true,
        ),
        const SosTransmissionStep(
          stepNumber: 3,
          title: 'Analyzing Network Connectivity',
          detail: 'No cellular or Wi-Fi internet access detected',
          isCompleted: true,
        ),
        const SosTransmissionStep(
          stepNumber: 4,
          title: 'Internet Transmission',
          detail: 'Skipped: Offline mode active (No cellular or Wi-Fi connectivity). Initiating offline LoRa failover.',
          isCompleted: false,
        ),
        const SosTransmissionStep(
          stepNumber: 5,
          title: 'Hardware LoRa Failover',
          detail: 'Connected to Physical SORYNTH ESP32 Node',
          isCompleted: true,
        ),
        SosTransmissionStep(
          stepNumber: 6,
          title: 'LoRa Mesh Relay Propagation',
          detail: emergency.status == EmergencyStatus.gatewayReceived
              ? 'Packet received by Gateway (${emergency.hopCount} hops verified)'
              : 'Relayed via LoRa mesh (${emergency.hopCount} hops)',
          isCompleted: emergency.status == EmergencyStatus.gatewayReceived,
          isInProgress: emergency.status != EmergencyStatus.gatewayReceived,
        ),
      ];
    }

    return [
      SosTransmissionStep(
        stepNumber: 1,
        title: 'Capturing GPS Fix',
        detail: gpsDetail,
        isCompleted: true,
      ),
      SosTransmissionStep(
        stepNumber: 2,
        title: 'Preparing Emergency Payload',
        detail: 'ID: ${emergency.emergencyId} • Cached in local offline storage',
        isCompleted: true,
      ),
      const SosTransmissionStep(
        stepNumber: 3,
        title: 'Analyzing Network Connectivity',
        detail: 'No cellular or Wi-Fi internet access detected',
        isCompleted: true,
      ),
      const SosTransmissionStep(
        stepNumber: 4,
        title: 'Internet Transmission',
        detail: 'Skipped: Offline mode active (No cellular or Wi-Fi connectivity). Initiating offline LoRa failover.',
        isCompleted: false,
      ),
      const SosTransmissionStep(
        stepNumber: 5,
        title: 'Hardware LoRa Failover',
        detail: 'No physical SORYNTH ESP32 connected via BLE. Alert queued locally (PENDING HARDWARE TRANSMISSION).',
        isFailed: true,
      ),
      const SosTransmissionStep(
        stepNumber: 6,
        title: 'LoRa Mesh Relay Propagation',
        detail: 'LoRa transmission halted: Waiting for physical ESP32 hardware transceiver.',
        isFailed: true,
      ),
    ];
  }

  /// Master Emergency SOS Dispatch Engine
  Stream<List<SosTransmissionStep>> dispatchEmergency({
    required EmergencyModel emergency,
    required void Function(EmergencyModel updated) onEmergencyUpdated,
  }) async* {
    List<SosTransmissionStep> steps = [
      const SosTransmissionStep(
        stepNumber: 1,
        title: 'Capturing GPS Fix',
        detail: 'Locking coordinates from device GPS...',
        isInProgress: true,
      ),
      const SosTransmissionStep(
        stepNumber: 2,
        title: 'Preparing Emergency Payload',
        detail: 'Generating unique ID and compact packet...',
      ),
      const SosTransmissionStep(
        stepNumber: 3,
        title: 'Analyzing Network Connectivity',
        detail: 'Probing cellular / Wi-Fi internet access...',
      ),
      const SosTransmissionStep(
        stepNumber: 4,
        title: 'Internet Transmission',
        detail: 'Transmitting alert directly to SORYNTH Cloud...',
      ),
      const SosTransmissionStep(
        stepNumber: 5,
        title: 'Hardware LoRa Failover',
        detail: 'Connecting to ESP32 transceiver via BLE...',
      ),
      const SosTransmissionStep(
        stepNumber: 6,
        title: 'LoRa Mesh Relay Propagation',
        detail: 'Transmitting packet over 868MHz LoRa mesh...',
      ),
    ];

    yield steps;

    // STEP 1: Verify and Lock GPS
    await Future.delayed(const Duration(milliseconds: 500));
    final bool hasValidCoords = emergency.hasValidCoordinates;
    final String gpsDetail = hasValidCoords
        ? (emergency.accuracy != null
            ? 'Lat: ${emergency.latitude.toStringAsFixed(4)}, Lng: ${emergency.longitude.toStringAsFixed(4)} (${emergency.accuracyQualityLabel})'
            : 'Lat: ${emergency.latitude.toStringAsFixed(4)}, Lng: ${emergency.longitude.toStringAsFixed(4)} (Approximate)')
        : 'Location unavailable (No GPS satellite fix acquired)';

    EmergencyModel currentEmergency = emergency.copyWith(
      status: EmergencyStatus.gpsLocked,
    );
    onEmergencyUpdated(currentEmergency);

    steps[0] = steps[0].copyWith(
      isCompleted: true,
      isInProgress: false,
      detail: gpsDetail,
    );
    steps[1] = steps[1].copyWith(isInProgress: true);
    yield steps;

    // STEP 2: Save to local storage (pending queue)
    await Future.delayed(const Duration(milliseconds: 400));
    currentEmergency = currentEmergency.copyWith(
      status: EmergencyStatus.queuedLocally,
      communicationMethod: CommunicationMethod.internet,
    );
    await _storageService.saveEmergency(currentEmergency);
    await _storageService.saveActiveEmergencyId(currentEmergency.emergencyId);
    onEmergencyUpdated(currentEmergency);

    steps[1] = steps[1].copyWith(
      isCompleted: true,
      isInProgress: false,
      detail: 'ID: ${emergency.emergencyId} • Cached in local offline storage',
    );
    steps[2] = steps[2].copyWith(isInProgress: true);
    yield steps;

    // STEP 3: Check Internet reachability
    final hasInternet = await _connectivityService.checkActualInternetReachability();
    steps[2] = steps[2].copyWith(
      isCompleted: true,
      isInProgress: false,
      detail: hasInternet
          ? 'Internet connection verified (Active)'
          : 'No cellular or Wi-Fi internet access detected',
    );

    // STEP 4: Internet Transmission Branch
    if (hasInternet) {
      if (_supabaseService.isConfigured) {
        steps[3] = steps[3].copyWith(isInProgress: true);
        yield steps;

        try {
          final res = await _supabaseService.submitSosAlert(currentEmergency);

          if (!isServerAcknowledgementConfirmed(res)) {
            throw Exception('Server rejected or did not confirm delivery: $res');
          }

          currentEmergency = currentEmergency.copyWith(
            status: EmergencyStatus.uploadedToServer,
            communicationMethod: CommunicationMethod.internet,
          );

          await _storageService.saveEmergency(currentEmergency);
          await _storageService.clearActiveEmergency();
          _notifyEmergencyUpdated(currentEmergency);
          onEmergencyUpdated(currentEmergency);

          steps[3] = steps[3].copyWith(
            isCompleted: true,
            isInProgress: false,
            detail: 'SOS successfully registered on SORYNTH Rescue Network (Server Delivery Confirmed)',
          );
          yield steps;
          // Successfully delivered online! Early return so we don't invoke LoRa unnecessarily
          return;
        } catch (e) {
          debugPrint('[EmergencyRepo] Cloud submission failed: $e. Initiating offline LoRa failover.');
          steps[3] = steps[3].copyWith(
            isCompleted: false,
            isInProgress: false,
            isFailed: true,
            detail: 'Cloud submission failed ($e). Initiating offline LoRa failover.',
          );
          yield steps;
        }
      } else {
        // Internet is active, but Supabase URL/Key is unconfigured
        steps[3] = steps[3].copyWith(
          isCompleted: false,
          isInProgress: false,
          detail: 'Skipped: SORYNTH Supabase backend not configured. Initiating offline LoRa failover.',
        );
        yield steps;
      }
    } else {
      // Internet is not active
      steps[3] = steps[3].copyWith(
        isCompleted: false,
        isInProgress: false,
        detail: 'Skipped: Offline mode active (No cellular or Wi-Fi connectivity). Initiating offline LoRa failover.',
      );
      yield steps;
    }

    // STEP 5: ESP32 Bluetooth Low Energy Connection
    steps[4] = steps[4].copyWith(isInProgress: true);
    yield steps;

    currentEmergency = currentEmergency.copyWith(
      status: EmergencyStatus.connectingToEsp32,
    );
    await _storageService.saveEmergency(currentEmergency);
    onEmergencyUpdated(currentEmergency);

    // Check Bluetooth adapter state
    final isBleReady = await _bluetoothService.isBluetoothSupportedAndEnabled();
    if (!isBleReady) {
      currentEmergency = currentEmergency.copyWith(
        status: EmergencyStatus.queuedLocally,
        wasQueuedOffline: true,
        communicationMethod: CommunicationMethod.internet,
      );
      await _storageService.saveEmergency(currentEmergency);
      onEmergencyUpdated(currentEmergency);

      steps[4] = steps[4].copyWith(
        isFailed: true,
        isInProgress: false,
        detail: 'Bluetooth is turned off or not supported. Alert queued locally (Awaiting Hardware Connection).',
      );
      steps[5] = steps[5].copyWith(
        isFailed: true,
        isInProgress: false,
        detail: 'LoRa transmission halted: No BLE connection to physical ESP32.',
      );
      yield steps;
      return;
    }

    // Check if physical ESP32 device is currently connected
    if (_bluetoothService.currentTelemetry.status != BleConnectionStatus.connected) {
      // Attempt quick scan/connect
      await _bluetoothService.startScan(timeout: const Duration(seconds: 4));
    }

    if (_bluetoothService.currentTelemetry.status != BleConnectionStatus.connected) {
      currentEmergency = currentEmergency.copyWith(
        status: EmergencyStatus.queuedLocally,
        wasQueuedOffline: true,
        communicationMethod: CommunicationMethod.internet,
      );
      await _storageService.saveEmergency(currentEmergency);
      onEmergencyUpdated(currentEmergency);

      steps[4] = steps[4].copyWith(
        isFailed: true,
        isInProgress: false,
        detail: 'No physical SORYNTH ESP32 connected via BLE. Alert queued locally (PENDING HARDWARE TRANSMISSION).',
      );
      steps[5] = steps[5].copyWith(
        isFailed: true,
        isInProgress: false,
        detail: 'LoRa transmission halted: Waiting for physical ESP32 hardware transceiver.',
      );
      yield steps;
      return;
    }

    steps[4] = steps[4].copyWith(
      isCompleted: true,
      isInProgress: false,
      detail: 'Connected to Physical SORYNTH ESP32 Node (${_bluetoothService.currentTelemetry.deviceName ?? "ESP32"})',
    );

    steps[5] = steps[5].copyWith(isInProgress: true);
    yield steps;

    // STEP 6: LoRa Radio & Mesh Relay Propagation
    currentEmergency = currentEmergency.copyWith(
      status: EmergencyStatus.transmittingViaLora,
    );
    await _storageService.saveEmergency(currentEmergency);
    onEmergencyUpdated(currentEmergency);

    final bleResult = await _bluetoothService.transmitEmergencyPacket(
      currentEmergency,
      onProgress: (progressMsg) {
        steps[5] = steps[5].copyWith(detail: progressMsg);
      },
    );

    if (bleResult.isSuccess) {
      // Real BLE connection and successful hardware acknowledgement verified!
      // If hopCount > 1, mesh forwarding was confirmed (LORA_RELAY).
      // If hopCount <= 1, direct ESP32 transceiver ACK was confirmed (BLUETOOTH_LORA).
      final confirmedMethod = (bleResult.hopCount > 1 || bleResult.relayNodes.length > 1)
          ? CommunicationMethod.loraRelay
          : CommunicationMethod.bluetoothLora;

      currentEmergency = currentEmergency.copyWith(
        communicationMethod: confirmedMethod,
        status: bleResult.finalStatus,
        hopCount: bleResult.hopCount,
        relayPath: bleResult.relayNodes,
      );
      await _storageService.saveEmergency(currentEmergency);
      onEmergencyUpdated(currentEmergency);

      steps[5] = steps[5].copyWith(
        isCompleted: true,
        isInProgress: false,
        detail: '${bleResult.message} (${bleResult.hopCount} hops verified)',
      );
    } else {
      // Hardware transmission failed or timed out: No hardware ACK was confirmed.
      currentEmergency = currentEmergency.copyWith(
        status: bleResult.finalStatus,
        wasQueuedOffline: true,
        communicationMethod: CommunicationMethod.internet,
      );
      await _storageService.saveEmergency(currentEmergency);
      onEmergencyUpdated(currentEmergency);

      steps[5] = steps[5].copyWith(
        isFailed: true,
        isInProgress: false,
        detail: bleResult.message,
      );
    }

    yield steps;
  }

  /// Synchronize all cached/offline emergencies to Supabase when internet returns
  Future<void> syncPendingEmergencies() async {
    if (_isSyncing) {
      debugPrint(
        '[EmergencyRepo] Sync already running. Skipping duplicate call.',
      );
      return;
    }

    _isSyncing = true;

    try {
      final pending = _storageService.getPendingEmergencies();

      if (pending.isEmpty || !_supabaseService.isConfigured) {
        return;
      }

      debugPrint(
        '[EmergencyRepo] Auto-syncing ${pending.length} offline emergencies to Supabase...',
      );

      for (final em in pending) {
        // Prevent duplicate uploads during retries if status changed in storage
        final current = _storageService.getEmergencyById(em.emergencyId);
        if (current != null && current.isServerConfirmed) {
          continue;
        }

        try {
          // Transmission source integrity:
          // A pending offline emergency uploaded via restored internet is a direct cloud upload (INTERNET).
          // Only if genuine physical LoRa/ESP32 hardware transmission was previously confirmed
          // (status is gatewayReceived or relayReceived, and method is bluetoothLora or loraRelay)
          // should a hardware transmission source be reported.
          final bool hasConfirmedHardwareTransmission =
              (em.status == EmergencyStatus.gatewayReceived ||
               em.status == EmergencyStatus.relayReceived) &&
              (em.communicationMethod == CommunicationMethod.bluetoothLora ||
               em.communicationMethod == CommunicationMethod.loraRelay);

          final CommunicationMethod methodForUpload = hasConfirmedHardwareTransmission
              ? em.communicationMethod
              : CommunicationMethod.internet;

          final alertToUpload = em.copyWith(
            communicationMethod: methodForUpload,
            wasQueuedOffline: true,
          );

          final res = await _supabaseService.submitSosAlert(alertToUpload);

          // Only after server acknowledgement is explicitly confirmed:
          if (!isServerAcknowledgementConfirmed(res)) {
            debugPrint(
              '[EmergencyRepo] Server did not explicitly acknowledge emergency ${em.emergencyId} ($res). Preserving pending status.',
            );
            continue;
          }

          final latest = _storageService.getEmergencyById(em.emergencyId) ?? alertToUpload;
          final synced = latest.copyWith(
            status: EmergencyStatus.uploadedToServer,
            communicationMethod: methodForUpload,
            wasQueuedOffline: true,
          );

          await _storageService.saveEmergency(synced);
          if (_storageService.getActiveEmergencyId() == em.emergencyId) {
            await _storageService.clearActiveEmergency();
          }
          _notifyEmergencyUpdated(synced);
          debugPrint(
            '[EmergencyRepo] Emergency ${em.emergencyId} successfully synced to Supabase (UPLOADED_TO_SERVER, method: ${methodForUpload.code}).',
          );
        } catch (e) {
          debugPrint(
            '[EmergencyRepo] Sync failed for ${em.emergencyId}: $e',
          );
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> cancelEmergency(String emergencyId) async {
    await _storageService.updateEmergencyStatus(
      emergencyId,
      EmergencyStatus.cancelled,
    );
    await _storageService.clearActiveEmergency();

    final cancelled = _storageService.getEmergencyById(emergencyId);
    if (cancelled != null) {
      _notifyEmergencyUpdated(cancelled);
    }

    if (await _connectivityService.checkActualInternetReachability() &&
        _supabaseService.isConfigured) {
      await _supabaseService.cancelEmergency(emergencyId);
    }
  }

  void dispose() {
    if (!_emergencyUpdatesController.isClosed) {
      _emergencyUpdatesController.close();
    }
  }

  Future<void> resolveEmergency(String emergencyId) async {
    await _storageService.updateEmergencyStatus(
      emergencyId,
      EmergencyStatus.resolved,
      resolvedAt: DateTime.now(),
    );
    if (_storageService.getActiveEmergencyId() == emergencyId) {
      await _storageService.clearActiveEmergency();
    }
    final resolved = _storageService.getEmergencyById(emergencyId);
    if (resolved != null) {
      _notifyEmergencyUpdated(resolved);
    }
  }

  Future<void> clearActiveEmergency() => _storageService.clearActiveEmergency();
  Future<void> saveActiveEmergencyId(String id) =>
      _storageService.saveActiveEmergencyId(id);

  List<EmergencyModel> getAllEmergencies() => _storageService.getAllEmergencies();
  EmergencyModel? getEmergency(String id) => _storageService.getEmergencyById(id);
  String? getActiveEmergencyId() => _storageService.getActiveEmergencyId();
}
