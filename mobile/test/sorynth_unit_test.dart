import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_constants.dart';
import 'package:sorynth/data/models/emergency_model.dart';
import 'package:sorynth/data/repositories/emergency_repository.dart';
import 'package:sorynth/data/services/bluetooth_service.dart';
import 'package:sorynth/data/services/connectivity_service.dart';
import 'package:sorynth/data/services/gps_service.dart';
import 'package:sorynth/data/services/offline_storage_service.dart';
import 'package:sorynth/data/services/supabase_service.dart';

// ==============================================================================
// TEST DOUBLES FOR ISOLATED UNIT TESTING WITHOUT EXTERNAL NETWORK/HARDWARE
// ==============================================================================

class FakeConnectivityService extends ConnectivityService {
  final bool hasReachability;

  FakeConnectivityService({
    required this.hasReachability,
  }) : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async {
    return hasReachability;
  }
}
class FakeSupabaseService extends SupabaseService {
  final bool isConfiguredOverride;
  final bool shouldSucceed;
  final String? failureMessage;
  int submitCallCount = 0;
  EmergencyModel? lastSubmitted;

  FakeSupabaseService({
    this.isConfiguredOverride = true,
    this.shouldSucceed = true,
    this.failureMessage,
  });

  @override
  bool get isConfigured => isConfiguredOverride;

  @override
  Future<Map<String, dynamic>> submitSosAlert(EmergencyModel emergency) async {
    submitCallCount++;
    lastSubmitted = emergency;
    if (!isConfiguredOverride) {
      throw Exception('Supabase backend is not configured.');
    }
    if (!shouldSucceed) {
      throw Exception(failureMessage ?? 'Network timeout: Connection refused (HTTP 503)');
    }
    return {
      'status': 'DELIVERED',
      'success': true,
      'emergency_id': emergency.emergencyId,
      'emergency_code': emergency.emergencyId,
    };
  }

  @override
  Future<bool> cancelEmergency(String emergencyCode, {String reason = 'User requested cancellation'}) async => true;
}

class MockEsp32BluetoothService implements BluetoothService {
  final _telemetryController = StreamController<BleTelemetry>.broadcast();
  BleTelemetry _telemetry = const BleTelemetry(
    status: BleConnectionStatus.connected,
    deviceName: 'SORYNTH-ESP32-TEST',
    deviceId: 'MOCK_ESP32_DEV_A1',
    rssi: -64,
    currentHops: 0,
    isSimulated: true,
    lastMessage: 'Test Mock ESP32 Ready',
  );

  @override
  bool get isSimulated => true;

  @override
  String get modeLabel => 'DEMO MODE (Simulated)';

  @override
  BleTelemetry get currentTelemetry => _telemetry;

  @override
  Stream<BleTelemetry> get telemetryStream => _telemetryController.stream;

  void _updateTelemetry(BleTelemetry updated) {
    _telemetry = updated;
    _telemetryController.add(_telemetry);
  }

  @override
  Future<bool> isBluetoothSupportedAndEnabled() async => true;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    _updateTelemetry(_telemetry.copyWith(status: BleConnectionStatus.scanning));
    await Future.delayed(const Duration(milliseconds: 10));
    _updateTelemetry(
      _telemetry.copyWith(
        status: BleConnectionStatus.connected,
        deviceName: 'SORYNTH-ESP32-TEST',
        deviceId: 'MOCK_ESP32_DEV_A1',
        rssi: -62,
      ),
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> connectToNode(String deviceId) async {
    _updateTelemetry(_telemetry.copyWith(status: BleConnectionStatus.connecting));
    await Future.delayed(const Duration(milliseconds: 10));
    _updateTelemetry(
      _telemetry.copyWith(
        status: BleConnectionStatus.connected,
        deviceName: 'SORYNTH-ESP32-TEST',
        deviceId: deviceId,
        rssi: -58,
      ),
    );
    return true;
  }

  @override
  Future<void> disconnect() async {
    _updateTelemetry(
      _telemetry.copyWith(
        status: BleConnectionStatus.disconnected,
        lastMessage: 'Disconnected from test mock',
      ),
    );
  }

  @override
  Future<BleTransmissionResult> transmitEmergencyPacket(
    EmergencyModel emergency, {
    void Function(String progressStep)? onProgress,
  }) async {
    _updateTelemetry(
      _telemetry.copyWith(
        status: BleConnectionStatus.transmitting,
        lastMessage: 'Test mock simulating LoRa transmission',
      ),
    );

    onProgress?.call('[TEST MODE] Test mock writing packet to BLE...');
    await Future.delayed(const Duration(milliseconds: 10));

    _updateTelemetry(
      _telemetry.copyWith(
        status: BleConnectionStatus.connected,
        currentHops: 2,
        rssi: -78,
        lastMessage: '[TEST MODE] Test mock LoRa ACK Verified',
      ),
    );

    return BleTransmissionResult(
      isSuccess: true,
      emergencyId: emergency.emergencyId,
      finalStatus: EmergencyStatus.gatewayReceived,
      hopCount: 2,
      relayNodes: const ['ESP32_RELAY_02', 'ESP32_GW_ALPHA'],
      isSimulated: true,
      message: '[TEST MODE] Test fixture LoRa transmission succeeded.',
      rssi: -78,
    );
  }

  @override
  void dispose() {
    _telemetryController.close();
  }
}

class FakeBluetoothServiceWithDisabledAdapter extends MockEsp32BluetoothService {
  @override
  bool get isSimulated => false;

  @override
  String get modeLabel => 'REAL HARDWARE MODE';

  @override
  BleTelemetry get currentTelemetry => const BleTelemetry(
        status: BleConnectionStatus.disconnected,
        isSimulated: false,
        lastMessage: 'Bluetooth adapter powered off',
      );

  @override
  Future<bool> isBluetoothSupportedAndEnabled() async => false;
}

class FakeRealBluetoothServiceDisconnected extends MockEsp32BluetoothService {
  @override
  bool get isSimulated => false;

  @override
  String get modeLabel => 'REAL HARDWARE MODE';

  @override
  BleTelemetry get currentTelemetry => const BleTelemetry(
        status: BleConnectionStatus.disconnected,
        isSimulated: false,
        lastMessage: 'Ready to scan',
      );

  @override
  Future<bool> isBluetoothSupportedAndEnabled() async => true;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 4)}) async {
    // Scan completes without finding hardware ESP32
  }
}

// ==============================================================================
// MAIN TEST SUITE
// ==============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AUDIT 1 & 2: Online SOS Submission & Offline Detection Flows', () {
    test('Online Flow: Successful Supabase RPC returns UPLOADED_TO_SERVER without invoking BLE/LoRa', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSupabaseService(shouldSucceed: true);
      final fakeConn = FakeConnectivityService(hasReachability: true);
      final mockBle = MockEsp32BluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: mockBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR_ONLINE_001',
        personId: 'CIVILIAN_101',
        personName: 'Priya Patel',
        latitude: 12.9141,
        longitude: 74.8560,
        accuracy: 6.2,
        emergencyType: EmergencyType.medical,
        message: 'Severe injury requiring immediate dispatch',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      EmergencyModel? updatedModel;
      List<SosTransmissionStep> finalSteps = [];

      await for (final steps in repo.dispatchEmergency(
        emergency: emergency,
        onEmergencyUpdated: (em) => updatedModel = em,
      )) {
        finalSteps = steps;
      }

      // Verify Step 3: Network verified
      expect(finalSteps[2].isCompleted, isTrue);
      expect(finalSteps[2].detail, contains('Internet connection verified (Active)'));

      // Verify Step 4: Cloud submission succeeded
      expect(finalSteps[3].isCompleted, isTrue);
      expect(finalSteps[3].detail, contains('Server Delivery Confirmed'));
      expect(fakeSupabase.submitCallCount, 1);

      // Verify Early Return: Steps 5 and 6 (BLE / LoRa) were NOT started
      expect(finalSteps[4].isInProgress, isFalse);
      expect(finalSteps[4].isCompleted, isFalse);
      expect(finalSteps[5].isInProgress, isFalse);

      // Verify emergency status
      expect(updatedModel?.status, EmergencyStatus.uploadedToServer);
      expect(updatedModel?.communicationMethod, CommunicationMethod.internet);
      expect(updatedModel?.acknowledgedAt, isNull);

    });

    test('Online Flow Failure: Cloud submission error triggers smooth fallback to offline LoRa failover', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSupabaseService(
        shouldSucceed: false,
        failureMessage: 'Gateway 504 Gateway Timeout',
      );
      final fakeConn = FakeConnectivityService(hasReachability: true);
      final mockBle = MockEsp32BluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: mockBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR_FAILOVER_001',
        personId: 'CIVILIAN_102',
        personName: 'Ravi Kumar',
        latitude: 13.0,
        longitude: 75.0,
        accuracy: 12.0,
        emergencyType: EmergencyType.fire,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      List<SosTransmissionStep> finalSteps = [];
      EmergencyModel? updatedModel;

      await for (final steps in repo.dispatchEmergency(
        emergency: emergency,
        onEmergencyUpdated: (em) => updatedModel = em,
      )) {
        finalSteps = steps;
      }

      // Step 4 marked failed with clear failover message
      expect(finalSteps[3].isFailed, isTrue);
      expect(finalSteps[3].detail, contains('Cloud submission failed'));
      expect(finalSteps[3].detail, contains('Initiating offline LoRa failover'));

      // Smoothly proceeded to Step 5 & 6
      expect(finalSteps[4].isCompleted, isTrue);
      expect(finalSteps[5].isCompleted, isTrue);
      expect(updatedModel?.status, EmergencyStatus.gatewayReceived);
    });

    test('Offline Detection: Network disabled immediately skips internet without claiming delivery', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSupabaseService();
      final fakeConn = FakeConnectivityService(hasReachability: false);
      final mockBle = MockEsp32BluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: mockBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR_OFFLINE_001',
        personId: 'CIVILIAN_103',
        personName: 'Anil Rao',
        latitude: 14.0,
        longitude: 74.5,
        emergencyType: EmergencyType.naturalDisaster,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      List<SosTransmissionStep> finalSteps = [];

      await for (final steps in repo.dispatchEmergency(
        emergency: emergency,
        onEmergencyUpdated: (_) {},
      )) {
        finalSteps = steps;
      }

      // Step 3 shows offline
      expect(finalSteps[2].detail, contains('No cellular or Wi-Fi internet access detected'));

      // Step 4 is skipped: never calls Supabase
      expect(finalSteps[3].isCompleted, isFalse);
      expect(finalSteps[3].detail, contains('Skipped: Offline mode active'));
      expect(fakeSupabase.submitCallCount, 0);

      // Proceded directly to offline LoRa pipeline
      expect(finalSteps[4].isCompleted, isTrue);
      expect(finalSteps[5].isCompleted, isTrue);
    });
  });

  group('AUDIT 3, 4, 5 & 6: Offline Hardware vs Simulation & Real BLE Behavior', () {
    test('Real Hardware Mode Disconnected: Refuses fake success and stores alert locally as QUEUED_LOCALLY', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSupabaseService();
      final fakeConn = FakeConnectivityService(hasReachability: false);
      final realBle = FakeRealBluetoothServiceDisconnected(); // Disconnected physical driver

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: realBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR_HW_DISCONNECTED',
        personId: 'CIVILIAN_201',
        personName: 'Sunita Menon',
        latitude: 12.8,
        longitude: 74.9,
        accuracy: 10.0,
        emergencyType: EmergencyType.lostStranded,
        communicationMethod: CommunicationMethod.bluetoothLora,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      EmergencyModel? updatedModel;
      List<SosTransmissionStep> finalSteps = [];

      await for (final steps in repo.dispatchEmergency(
        emergency: emergency,
        onEmergencyUpdated: (em) => updatedModel = em,
      )) {
        finalSteps = steps;
      }

      // Step 5 reports failure: No physical ESP32 connected
      expect(finalSteps[4].isFailed, isTrue);
      expect(finalSteps[4].detail, contains('No physical SORYNTH ESP32 connected via BLE'));
      expect(finalSteps[4].detail, contains('PENDING HARDWARE TRANSMISSION'));

      // Step 6 halted
      expect(finalSteps[5].isFailed, isTrue);
      expect(finalSteps[5].detail, contains('LoRa transmission halted'));

      // Status remains queuedLocally (PENDING), never claiming delivery!
      expect(updatedModel?.status, EmergencyStatus.queuedLocally);
      final stored = storage.getEmergencyById('SOR_HW_DISCONNECTED');
      expect(stored?.status, EmergencyStatus.queuedLocally);
      expect(storage.getPendingEmergencies().length, 1);
    });

    test('Real Hardware Mode with Bluetooth Disabled: Halts immediately and saves alert locally', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSupabaseService();
      final fakeConn = FakeConnectivityService(hasReachability: false);
      final disabledBle = FakeBluetoothServiceWithDisabledAdapter();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: disabledBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR_BLE_DISABLED',
        personId: 'CIVILIAN_202',
        personName: 'Vikram',
        latitude: 12.9,
        longitude: 74.8,
        emergencyType: EmergencyType.medical,
        communicationMethod: CommunicationMethod.bluetoothLora,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      List<SosTransmissionStep> finalSteps = [];
      EmergencyModel? updatedModel;

      await for (final steps in repo.dispatchEmergency(
        emergency: emergency,
        onEmergencyUpdated: (em) => updatedModel = em,
      )) {
        finalSteps = steps;
      }

      expect(finalSteps[4].isFailed, isTrue);
      expect(finalSteps[4].detail, contains('Bluetooth is turned off or not supported'));
      expect(finalSteps[5].isFailed, isTrue);
      expect(updatedModel?.status, EmergencyStatus.queuedLocally);
      expect(storage.getPendingEmergencies().length, 1);
    });

    test('Demo Mode: Explicitly labeled as [TEST MODE / SIMULATED] in telemetry and steps', () async {
      final mockBle = MockEsp32BluetoothService();
      expect(mockBle.isSimulated, isTrue);
      expect(mockBle.modeLabel, contains('DEMO MODE'));
      expect(mockBle.currentTelemetry.isSimulated, isTrue);

      final emergency = EmergencyModel(
        emergencyId: 'SOR_DEMO_001',
        personId: 'TESTER_01',
        personName: 'QA Engineer',
        latitude: 12.9,
        longitude: 74.8,
        emergencyType: EmergencyType.other,
        communicationMethod: CommunicationMethod.bluetoothLora,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      final List<String> progressLogs = [];
      final result = await mockBle.transmitEmergencyPacket(
        emergency,
        onProgress: (step) => progressLogs.add(step),
      );

      expect(result.isSuccess, isTrue);
      expect(result.isSimulated, isTrue);
      expect(result.finalStatus, EmergencyStatus.gatewayReceived);
      expect(result.hopCount, 2);
      expect(result.relayNodes, ['ESP32_RELAY_02', 'ESP32_GW_ALPHA']);
      expect(result.message, contains('[TEST MODE]'));

      for (final log in progressLogs) {
        expect(log, contains('[TEST MODE]'));
      }
    });
  });

  group('AUDIT 7 & 8: GPS Accuracy, Duplicates & Status Transitions', () {
    test('GPS Accuracy: Accurately differentiates precise (<=30m) vs approximate (>30m) location', () {
      final precise = GpsResult(
        isSuccess: true,
        latitude: 12.9141,
        longitude: 74.8560,
        accuracy: 4.8, // Direct satellite fix
        timestamp: DateTime.now(),
      );
      expect(precise.quality, GpsQuality.accurate);
      expect(precise.isAccurate, isTrue);
      expect(precise.isApproximate, isFalse);
      expect(precise.qualityBadgeLabel, contains('Precise GPS Fix'));

      final approx = GpsResult(
        isSuccess: true,
        latitude: 12.9141,
        longitude: 74.8560,
        accuracy: 95.0, // Cell-tower triangulation
        timestamp: DateTime.now(),
      );
      expect(approx.quality, GpsQuality.approximate);
      expect(approx.isAccurate, isFalse);
      expect(approx.isApproximate, isTrue);
      expect(approx.qualityBadgeLabel, contains('Approximate Fix'));
      expect(approx.warningMessage, contains('High-precision satellite lock pending'));

      final disabled = GpsResult.failure(
        message: 'Location service disabled',
        isServiceDisabled: true,
      );
      expect(disabled.quality, GpsQuality.unavailable);
      expect(disabled.isServiceDisabled, isTrue);
    });

    test('Duplicate Prevention: Updating an existing emergency updates in-place without duplicating', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);

      final em = EmergencyModel(
        emergencyId: 'SOR_UNIQUE_999',
        personId: 'USER_01',
        personName: 'Unique User',
        latitude: 12.0,
        longitude: 74.0,
        emergencyType: EmergencyType.accident,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      await storage.saveEmergency(em);
      expect(storage.getAllEmergencies().length, 1);

      // Re-saving with new status
      final emUpdated = em.copyWith(status: EmergencyStatus.uploadedToServer);
      await storage.saveEmergency(emUpdated);

      expect(storage.getAllEmergencies().length, 1);
      expect(storage.getEmergencyById('SOR_UNIQUE_999')?.status, EmergencyStatus.uploadedToServer);
    });

    test('Cancellation Workflow: Marks emergency CANCELLED and clears active tracking', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSupabaseService();
      final fakeConn = FakeConnectivityService(hasReachability: true);

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: MockEsp32BluetoothService(),
        connectivityService: fakeConn,
        storageService: storage,
      );

      final em = EmergencyModel(
        emergencyId: 'SOR_TO_CANCEL',
        personId: 'USER_02',
        personName: 'Test Civilian',
        latitude: 12.0,
        longitude: 74.0,
        emergencyType: EmergencyType.other,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime.now(),
      );

      await storage.saveEmergency(em);
      await storage.saveActiveEmergencyId('SOR_TO_CANCEL');
      expect(storage.getActiveEmergencyId(), 'SOR_TO_CANCEL');

      await repo.cancelEmergency('SOR_TO_CANCEL');

      expect(storage.getActiveEmergencyId(), isNull);
      expect(storage.getEmergencyById('SOR_TO_CANCEL')?.status, EmergencyStatus.cancelled);
    });

    test('Compact 32-Byte LoRa Packet Serialization preserves coordinate precision and truncates message', () {
      final emergency = EmergencyModel(
        emergencyId: 'SOR123456',
        personId: 'USER_03',
        personName: 'Long Name Civilian',
        latitude: 12.914142345,
        longitude: 74.856012345,
        accuracy: 4.8,
        emergencyType: EmergencyType.medical,
        message: 'This is an extremely long distress message that exceeds the maximum LoRa BLE frame limit of 40 characters',
        communicationMethod: CommunicationMethod.bluetoothLora,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime(2026, 11, 5, 2, 0, 0),
        hopCount: 1,
      );

      final payload = emergency.toLoRaPayload();

      expect(payload['id'], 'SOR123456');
      expect(payload['t'], 'MEDICAL');
      expect(payload['lat'], 12.914142); // 6 decimal digits precision
      expect(payload['lng'], 74.856012);
      expect(payload['acc'], 5);
      expect(payload['hops'], 1);
      expect((payload['m'] as String).length, lessThanOrEqualTo(40));
    });
  });

  group('AUDIT: SOS Custom-Description & Category Selection Specification', () {
    test('Exact victim description maps to EmergencyModel.message and JSON/RPC payloads', () async {
      const victimCustomMessage =
          'Trapped on 2nd floor, stairwell collapsed, 2 elderly victims with asthma needing oxygen support';

      final emergency = EmergencyModel(
        emergencyId: 'SOR_CUSTOM_DESC_01',
        personId: 'CIVILIAN_USER_501',
        personName: 'Sunita Rao',
        phone: '+919876543210',
        latitude: 12.9200,
        longitude: 74.8600,
        accuracy: 8.5,
        emergencyType: EmergencyType.fire,
        message: victimCustomMessage,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      // Verify exact model mapping
      expect(emergency.message, victimCustomMessage);
      expect(emergency.emergencyType, EmergencyType.fire);

      // Verify JSON serialization maps to both 'message' and 'custom_message'
      final jsonMap = emergency.toJson();
      expect(jsonMap['message'], victimCustomMessage);
      expect(jsonMap['custom_message'], victimCustomMessage);
      expect(jsonMap['emergency_type'], 'FIRE');

      // Verify Supabase RPC submission sends exact victim description in p_custom_message
      final fakeSupabase = FakeSupabaseService(shouldSucceed: true);
      await fakeSupabase.submitSosAlert(emergency);

      expect(fakeSupabase.submitCallCount, 1);
      expect(fakeSupabase.lastSubmitted?.message, victimCustomMessage);
      expect(fakeSupabase.lastSubmitted?.toJson()['custom_message'], victimCustomMessage);

      // Verify LoRa payload truncates packet to 40 characters while EmergencyModel retains full text
      final loraPayload = emergency.toLoRaPayload();
      expect(loraPayload['m'], victimCustomMessage.substring(0, 40));
      expect(emergency.message.length, greaterThan(40));
      expect(emergency.message, victimCustomMessage);
    });

    test('Delivery status labels only claim server delivery after server confirmation', () {
      final queuedAlert = EmergencyModel(
        emergencyId: 'SOR_STATUS_01',
        personId: 'CIVILIAN_1',
        personName: 'Test Civilian',
        latitude: 12.0,
        longitude: 74.0,
        emergencyType: EmergencyType.medical,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      // Queued locally must NOT claim server delivery
      expect(queuedAlert.isServerConfirmed, isFalse);
      expect(queuedAlert.deliveryStatusLabel, contains('Pending Server Delivery'));
      expect(queuedAlert.deliveryStatusLabel, isNot(contains('Server Delivery Confirmed')));

      // LoRa gateway received must NOT claim server delivery
      final gatewayAlert = queuedAlert.copyWith(
        status: EmergencyStatus.gatewayReceived,
        communicationMethod: CommunicationMethod.bluetoothLora,
      );
      expect(gatewayAlert.isServerConfirmed, isFalse);
      expect(gatewayAlert.deliveryStatusLabel, contains('LoRa Gateway Received'));
      expect(gatewayAlert.deliveryStatusLabel, contains('Server Uplink Pending'));
      expect(gatewayAlert.deliveryStatusLabel, isNot(contains('Server Delivery Confirmed')));

      // Uploaded to server (ACK verified) DOES claim server delivery
      final serverConfirmedAlert = queuedAlert.copyWith(
        status: EmergencyStatus.uploadedToServer,
      );
      expect(serverConfirmedAlert.isServerConfirmed, isTrue);
      expect(serverConfirmedAlert.deliveryStatusLabel, 'Server Delivery Confirmed');
    });
  });
}
