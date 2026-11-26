import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_constants.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/data/models/emergency_model.dart';
import 'package:sorynth/data/repositories/emergency_repository.dart';
import 'package:sorynth/data/services/bluetooth_service.dart';
import 'package:sorynth/data/services/connectivity_service.dart';
import 'package:sorynth/data/services/offline_storage_service.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/emergency/sos_sending_screen.dart';
import 'package:sorynth/features/tracking/sos_active_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:sorynth/core/routing/app_router.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/features/splash/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =============================================================================
// TEST DOUBLES
// =============================================================================

class FakeSyncConnectivityService extends ConnectivityService {
  bool hasReachability;

  FakeSyncConnectivityService({this.hasReachability = true})
      : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async => hasReachability;
}

class FakeSyncSupabaseService extends SupabaseService {
  bool shouldSucceed;
  int submitCallCount = 0;
  EmergencyModel? lastSubmitted;
  Map<String, dynamic>? customResponse;
  User? fakeUser;

  FakeSyncSupabaseService({this.shouldSucceed = true, this.customResponse, this.fakeUser});

  @override
  User? get currentUser => fakeUser;

  @override
  bool get isConfigured => true;

  @override
  Future<Map<String, dynamic>> submitSosAlert(EmergencyModel emergency) async {
    submitCallCount++;
    lastSubmitted = emergency;
    if (!shouldSucceed) {
      throw Exception('503 Service Unavailable: Uplink rejected');
    }
    if (customResponse != null) {
      return customResponse!;
    }
    return {
      'status': 'DELIVERED',
      'success': true,
      'emergency_id': emergency.emergencyId,
      'emergency_code': emergency.emergencyId,
    };
  }

  @override
  Future<EmergencyModel?> getEmergencyStatus(String emergencyCode) async {
    return null; // Force reliance on local sync & repository updates
  }

  @override
  Future<bool> cancelEmergency(String emergencyCode,
          {String reason = 'User requested cancellation'}) async =>
      true;
}

class FakeSyncBluetoothService implements BluetoothService {
  final _telemetryController = StreamController<BleTelemetry>.broadcast();
  final BleTelemetry _telemetry = const BleTelemetry(
    status: BleConnectionStatus.disconnected,
    deviceName: 'TEST-ESP32',
    deviceId: 'DEV_001',
    rssi: 0,
    currentHops: 0,
    isSimulated: true,
  );

  @override
  bool get isSimulated => true;
  @override
  String get modeLabel => 'TEST';
  @override
  BleTelemetry get currentTelemetry => _telemetry;
  @override
  Stream<BleTelemetry> get telemetryStream => _telemetryController.stream;
  @override
  Future<bool> isBluetoothSupportedAndEnabled() async => true;
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 4)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> connectToNode(String deviceId) async => false;
  @override
  Future<void> disconnect() async {}
  @override
  Future<BleTransmissionResult> transmitEmergencyPacket(EmergencyModel emergency,
          {void Function(String progressStep)? onProgress}) async =>
      BleTransmissionResult(
        isSuccess: false,
        emergencyId: emergency.emergencyId,
        message: 'No hardware',
        finalStatus: EmergencyStatus.queuedLocally,
        isSimulated: true,
      );
  @override
  void dispose() {
    _telemetryController.close();
  }
}

class FakeHardwareAckBluetoothService extends FakeSyncBluetoothService {
  final BleTransmissionResult result;

  FakeHardwareAckBluetoothService(this.result);

  @override
  BleTelemetry get currentTelemetry => const BleTelemetry(
        status: BleConnectionStatus.connected,
        deviceName: 'SORYNTH_ESP32_NODE_01',
        deviceId: 'DEV_HW_001',
        isSimulated: false,
      );

  @override
  Future<BleTransmissionResult> transmitEmergencyPacket(
    EmergencyModel emergency, {
    void Function(String progressStep)? onProgress,
  }) async {
    return result;
  }
}

// =============================================================================
// TEST SUITE
// =============================================================================

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Offline SOS Sync & Status Update Specification', () {
    test('Offline SOS saved as Pending in local storage', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);

      final emergency = EmergencyModel(
        emergencyId: 'SOR803232',
        personId: 'CIVILIAN_GUEST',
        personName: 'Rohan Sharma',
        phone: '+919876543210',
        latitude: 12.9141,
        longitude: 74.8560,
        accuracy: 14.2,
        emergencyType: EmergencyType.naturalDisaster,
        message: 'Flash flood rising, stuck on rooftop',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime(2026, 11, 22, 10, 0, 0),
        isGuest: true,
      );

      await storage.saveEmergency(emergency);
      await storage.saveActiveEmergencyId(emergency.emergencyId);

      final retrieved = storage.getEmergencyById('SOR803232');
      expect(retrieved, isNotNull);
      expect(retrieved!.status, EmergencyStatus.queuedLocally);
      expect(retrieved.isServerConfirmed, isFalse);
      expect(retrieved.deliveryStatusLabel,
          'Queued Locally (Pending Server Delivery)');

      final pendingList = storage.getPendingEmergencies();
      expect(pendingList.any((e) => e.emergencyId == 'SOR803232'), isTrue);
    });

    test('Successful sync updates local status, preserves fields, and confirms server delivery',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
      final fakeConn = FakeSyncConnectivityService(hasReachability: true);
      final fakeBle = FakeSyncBluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final initialTimestamp = DateTime(2026, 11, 22, 10, 15, 0);
      final emergency = EmergencyModel(
        emergencyId: 'SOR803232',
        personId: 'USER_777',
        personName: 'Vikram Seth',
        phone: '+919988776655',
        latitude: 15.3647,
        longitude: 75.1240,
        accuracy: 9.8,
        emergencyType: EmergencyType.medical,
        message: 'Severe cardiac discomfort, oxygen required',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: initialTimestamp,
        hopCount: 2,
        relayPath: const ['NODE_A', 'NODE_B'],
        isGuest: false,
      );

      await storage.saveEmergency(emergency);
      await storage.saveActiveEmergencyId('SOR803232');

      // Trigger sync
      await repo.syncPendingEmergencies();

      // 1. Verify Supabase submit was called
      expect(fakeSupabase.submitCallCount, 1);
      expect(fakeSupabase.lastSubmitted?.emergencyId, 'SOR803232');

      // 2. Verify local storage record was updated to uploadedToServer
      final updated = storage.getEmergencyById('SOR803232');
      expect(updated, isNotNull);
      expect(updated!.status, EmergencyStatus.uploadedToServer);
      expect(updated.isServerConfirmed, isTrue);
      expect(updated.deliveryStatusLabel, 'Server Delivery Confirmed');

      // 3. Verify ALL existing fields are preserved
      expect(updated.emergencyId, 'SOR803232');
      expect(updated.personId, 'USER_777');
      expect(updated.personName, 'Vikram Seth');
      expect(updated.phone, '+919988776655');
      expect(updated.latitude, 15.3647);
      expect(updated.longitude, 75.1240);
      expect(updated.accuracy, 9.8);
      expect(updated.emergencyType, EmergencyType.medical);
      expect(updated.message, 'Severe cardiac discomfort, oxygen required');
      expect(updated.timestamp, initialTimestamp);
      expect(updated.hopCount, 2);
      expect(updated.relayPath, const ['NODE_A', 'NODE_B']);
      expect(updated.isGuest, isFalse);

      // 4. Verify it is removed from the pending retry queue
      expect(storage.getPendingEmergencies().any((e) => e.emergencyId == 'SOR803232'),
          isFalse);
    });

    test('Failed upload remains Pending and can retry without duplicate uploads',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: false);
      final fakeConn = FakeSyncConnectivityService(hasReachability: true);
      final fakeBle = FakeSyncBluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR803233',
        personId: 'GUEST_999',
        personName: 'Sunita Mehra',
        latitude: 18.5204,
        longitude: 73.8567,
        accuracy: 25.0,
        emergencyType: EmergencyType.fire,
        message: 'Building electrical fire on 4th floor',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime(2026, 11, 22, 10, 30, 0),
      );

      await storage.saveEmergency(emergency);

      // First sync attempt: Server fails (e.g. 503 Gateway / Network timeout)
      await repo.syncPendingEmergencies();

      expect(fakeSupabase.submitCallCount, 1);
      final failedRecord = storage.getEmergencyById('SOR803233');
      expect(failedRecord!.status, EmergencyStatus.queuedLocally);
      expect(failedRecord.isServerConfirmed, isFalse);
      expect(storage.getPendingEmergencies().any((e) => e.emergencyId == 'SOR803233'),
          isTrue);

      // Fix server connection: Second sync attempt succeeds
      fakeSupabase.shouldSucceed = true;
      await repo.syncPendingEmergencies();

      expect(fakeSupabase.submitCallCount, 2);
      final syncedRecord = storage.getEmergencyById('SOR803233');
      expect(syncedRecord!.status, EmergencyStatus.uploadedToServer);
      expect(syncedRecord.isServerConfirmed, isTrue);
      expect(storage.getPendingEmergencies().any((e) => e.emergencyId == 'SOR803233'),
          isFalse);

      // Third sync attempt: Verify duplicate upload is prevented
      await repo.syncPendingEmergencies();
      expect(fakeSupabase.submitCallCount, 2); // Did not increase
    });

    testWidgets('Tracking page displays Delivered after acknowledgement via Riverpod provider',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
      final fakeConn = FakeSyncConnectivityService(hasReachability: false);
      final fakeBle = FakeSyncBluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR803234',
        personId: 'CIVILIAN_888',
        personName: 'Deepak Joshi',
        latitude: 19.0760,
        longitude: 72.8777,
        accuracy: 11.0,
        emergencyType: EmergencyType.accident,
        message: 'Highway collision, 2 injured',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime(2026, 11, 22, 10, 45, 0),
      );

      await storage.saveEmergency(emergency);
      await storage.saveActiveEmergencyId('SOR803234');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            emergencyRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: SosActiveScreen(initialEmergency: emergency),
          ),
        ),
      );

      // Advance frames without hanging on repeating radar AnimationController
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Initial State: Shows Pending / Queued Locally
      expect(find.text('Queued Locally (Pending Server Delivery)'), findsOneWidget);
      expect(find.text('Queued Locally (Pending Hardware / Network)'), findsOneWidget);
      expect(find.text('Server Delivery Confirmed'), findsNothing);
      expect(find.text('Uploaded to SORYNTH Server'), findsNothing);

      // 2. Perform background sync (internet restored)
      fakeConn.hasReachability = true;
      await repo.syncPendingEmergencies();

      // 3. Pump frames to trigger Riverpod provider listener and UI update
      await tester.pump(const Duration(milliseconds: 100));

      // 4. Verified: Tracking page dynamically refreshed to Delivered!
      expect(find.text('Server Delivery Confirmed'), findsOneWidget);
      expect(find.text('Uploaded to SORYNTH Server'), findsOneWidget);
      expect(find.text('Queued Locally (Pending Server Delivery)'), findsNothing);
    });

    test('getPipelineSteps correctly differentiates offline-queued-then-synced vs direct online alerts', () async {
      final prefs = await SharedPreferences.getInstance();
      final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
      final fakeConn = FakeSyncConnectivityService(hasReachability: true);
      final fakeBle = FakeSyncBluetoothService();
      final storage = OfflineStorageService(prefs);

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final offlineSynced = EmergencyModel(
        emergencyId: 'SOR803232',
        personId: 'CIVILIAN_GUEST',
        personName: 'Rohan Sharma',
        latitude: 12.9141,
        longitude: 74.8560,
        accuracy: 14.2,
        emergencyType: EmergencyType.naturalDisaster,
        message: 'Flash flood rising',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime(2026, 11, 22, 10, 0, 0),
        wasQueuedOffline: true,
      );

      final steps = repo.getPipelineSteps(offlineSynced);
      expect(steps.length, 6);
      expect(steps.every((s) => s.isCompleted), isTrue);

      // Step 3: Network Connectivity
      expect(steps[2].detail, contains('Internet connection available'));
      expect(steps[2].detail, contains('Restored after initial offline queue'));

      // Step 4: Internet Transmission
      expect(steps[3].detail, contains('Internet transmission successful'));
      expect(steps[3].detail, contains('Server acknowledgement received'));

      // Step 5: Offline queue resolution
      expect(steps[4].detail, contains('Offline queue resolved'));

      // Step 6: Server acknowledgement confirmation
      expect(steps[5].detail, contains('Server acknowledgement confirmed'));
    });

    testWidgets('SosSendingScreen refreshes pipeline steps and displays Delivered Successfully when server acknowledgement received',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
      final fakeConn = FakeSyncConnectivityService(hasReachability: false);
      final fakeBle = FakeSyncBluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final emergency = EmergencyModel(
        emergencyId: 'SOR803235',
        personId: 'USER_101',
        personName: 'Priya Patel',
        latitude: 13.0827,
        longitude: 80.2707,
        accuracy: 12.0,
        emergencyType: EmergencyType.medical,
        message: 'Severe breathing difficulty',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime(2026, 11, 22, 11, 0, 0),
        wasQueuedOffline: true,
      );

      await storage.saveEmergency(emergency);
      await storage.saveActiveEmergencyId('SOR803235');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            emergencyRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: SosSendingScreen(emergency: emergency),
          ),
        ),
      );

      // Let initial dispatch complete in offline failover
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 5));

      // Initial state: shows offline telemetry
      expect(find.text('Transmission Pipeline Telemetry'), findsOneWidget);
      expect(find.text('Queued Locally (Pending Server Delivery)'), findsOneWidget);
      expect(find.text('Delivered Successfully'), findsNothing);

      // Restore internet & run background sync
      fakeConn.hasReachability = true;
      await repo.syncPendingEmergencies();

      // Trigger UI rebuild
      await tester.pump(const Duration(milliseconds: 100));

      // Verified: Refreshed telemetry and status
      expect(find.text('Delivered Successfully'), findsOneWidget);
      expect(find.text('Queued Locally (Pending Server Delivery)'), findsNothing);
      expect(find.textContaining('Internet connection available'), findsOneWidget);
      expect(find.textContaining('Internet transmission successful'), findsOneWidget);
      expect(find.textContaining('Server acknowledgement'), findsWidgets);
    });

    testWidgets('SosSendingScreen opened for already server-confirmed emergency loads pipeline without re-dispatching',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
      final fakeConn = FakeSyncConnectivityService(hasReachability: true);
      final fakeBle = FakeSyncBluetoothService();

      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final confirmed = EmergencyModel(
        emergencyId: 'SOR803236',
        personId: 'USER_102',
        personName: 'Karan Mehra',
        latitude: 28.7041,
        longitude: 77.1025,
        accuracy: 10.0,
        emergencyType: EmergencyType.fire,
        message: 'Kitchen fire',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime(2026, 11, 22, 11, 10, 0),
        wasQueuedOffline: true,
      );

      await storage.saveEmergency(confirmed);
      await storage.saveActiveEmergencyId('SOR803236');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            emergencyRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: SosSendingScreen(emergency: confirmed),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Verified: Immediately rendered as Delivered Successfully without duplicate upload
      expect(find.text('Delivered Successfully'), findsOneWidget);
      expect(find.textContaining('Internet connection available'), findsOneWidget);
      expect(find.textContaining('Internet transmission successful'), findsOneWidget);
      expect(fakeSupabase.submitCallCount, 0); // No duplicate dispatch/upload
    });

    group('Server Acknowledgement Contract & Verification', () {
      test('isServerAcknowledgementConfirmed identifies exact success shapes', () {
        // 1. Standard success from submit_sos_alert RPC
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'success': true,
            'is_duplicate': false,
            'emergency_id': 'c3b88b0a-7e61-4c6d-9799-a9a7a6b8c4d2',
            'emergency_code': 'SOR803232',
            'status': 'DELIVERED',
            'created_at': '2026-11-22T10:00:00Z',
          }),
          isTrue,
        );

        // 2. Duplicate submission success
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'success': true,
            'is_duplicate': true,
            'emergency_id': 'c3b88b0a-7e61-4c6d-9799-a9a7a6b8c4d2',
            'emergency_code': 'SOR803232',
            'status': 'DELIVERED',
            'created_at': '2026-11-22T10:00:00Z',
          }),
          isTrue,
        );
      });

      test('isServerAcknowledgementConfirmed rejects mere presence of emergency_id or emergency_code without explicit success', () {
        // Payload has emergency_id and emergency_code, but lacks success: true
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'emergency_id': 'c3b88b0a-7e61-4c6d-9799-a9a7a6b8c4d2',
            'emergency_code': 'SOR803232',
          }),
          isFalse,
        );

        // Payload has status DELIVERED, but lacks success: true
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'emergency_id': 'SOR803232',
            'emergency_code': 'SOR803232',
            'status': 'DELIVERED',
          }),
          isFalse,
        );
      });

      test('isServerAcknowledgementConfirmed rejects explicit failures and error payloads', () {
        // Explicit success: false
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'success': false,
            'emergency_id': 'SOR803232',
            'error': 'Database rate limit exceeded',
          }),
          isFalse,
        );

        // Inconsistent payload with error note
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'success': true,
            'error': 'Write rejected by row-level security policy',
          }),
          isFalse,
        );

        // Failure status indicators
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'success': true,
            'status': 'FAILED',
          }),
          isFalse,
        );
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({
            'success': true,
            'status': 'ERROR',
          }),
          isFalse,
        );
      });

      test('isServerAcknowledgementConfirmed rejects malformed and non-map responses', () {
        expect(EmergencyRepository.isServerAcknowledgementConfirmed(null), isFalse);
        expect(EmergencyRepository.isServerAcknowledgementConfirmed(''), isFalse);
        expect(EmergencyRepository.isServerAcknowledgementConfirmed(100), isFalse);
        expect(EmergencyRepository.isServerAcknowledgementConfirmed([]), isFalse);
        expect(EmergencyRepository.isServerAcknowledgementConfirmed({}), isFalse);
        expect(
          EmergencyRepository.isServerAcknowledgementConfirmed({'success': 'true'}), // String 'true' is not boolean true
          isFalse,
        );
      });

      test('syncPendingEmergencies rejects missing acknowledgement and keeps alert Pending', () async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);

        // Supabase returns a response with emergency_id and emergency_code, but missing success: true!
        final fakeSupabase = FakeSyncSupabaseService(
          customResponse: {
            'emergency_id': 'SOR_NO_ACK_1',
            'emergency_code': 'SOR_NO_ACK_1',
            'status': 'DELIVERED',
            // Missing 'success': true
          },
        );
        final fakeConn = FakeSyncConnectivityService(hasReachability: true);
        final fakeBle = FakeSyncBluetoothService();

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConn,
          storageService: storage,
        );

        final emergency = EmergencyModel(
          emergencyId: 'SOR_NO_ACK_1',
          personId: 'CIVILIAN_TEST',
          personName: 'Test Civilian',
          latitude: 12.9141,
          longitude: 74.8560,
          accuracy: 10.0,
          emergencyType: EmergencyType.medical,
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.queuedLocally,
          timestamp: DateTime(2026, 11, 22, 10, 0, 0),
        );

        await storage.saveEmergency(emergency);

        // Trigger sync
        await repo.syncPendingEmergencies();

        // Verification: Must NOT be marked uploadedToServer because explicit success confirmation is absent
        final recordAfterSync = storage.getEmergencyById('SOR_NO_ACK_1');
        expect(recordAfterSync!.status, EmergencyStatus.queuedLocally);
        expect(recordAfterSync.isServerConfirmed, isFalse);
        expect(storage.getPendingEmergencies().any((e) => e.emergencyId == 'SOR_NO_ACK_1'), isTrue);

        // Now provide explicit success confirmation:
        fakeSupabase.customResponse = {
          'success': true,
          'status': 'DELIVERED',
          'emergency_id': 'SOR_NO_ACK_1',
          'emergency_code': 'SOR_NO_ACK_1',
        };

        await repo.syncPendingEmergencies();

        final confirmedRecord = storage.getEmergencyById('SOR_NO_ACK_1');
        expect(confirmedRecord!.status, EmergencyStatus.uploadedToServer);
        expect(confirmedRecord.isServerConfirmed, isTrue);
        expect(confirmedRecord.deliveryStatusLabel, 'Server Delivery Confirmed');
      });

      testWidgets('SosActiveScreen does not overflow on narrow Android screen with long UUID',
          (tester) async {
        // Configure narrow Android screen (320px logical width)
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
        final fakeConn = FakeSyncConnectivityService(hasReachability: false);
        final fakeBle = FakeSyncBluetoothService();

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConn,
          storageService: storage,
        );

        final longUuidEmergency = EmergencyModel(
          emergencyId: '18221261-78fa-4d84-9c40-f70b2a3c4d5e',
          personId: 'USER_UUID_TEST',
          personName: 'Rohan Sharma',
          latitude: 12.9141,
          longitude: 74.8560,
          accuracy: 14.2,
          emergencyType: EmergencyType.naturalDisaster,
          message: 'Flash flood rising on rooftop',
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.uploadedToServer,
          timestamp: DateTime(2026, 11, 22, 11, 45, 0),
        );

        await storage.saveEmergency(longUuidEmergency);
        await storage.saveActiveEmergencyId(longUuidEmergency.emergencyId);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              offlineStorageServiceProvider.overrideWithValue(storage),
              supabaseServiceProvider.overrideWithValue(fakeSupabase),
              emergencyRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              home: SosActiveScreen(initialEmergency: longUuidEmergency),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));

        // Verifications:
        // 1. No RenderFlex overflow exception thrown on narrow screen
        expect(tester.takeException(), isNull);

        // 2. Truncated UUID Text and StatusBadge coexist cleanly within constrained bounds
        expect(find.text('18221261-78fa-4d84-9c40-f70b2a3c4d5e'), findsOneWidget); // Hero card
        expect(find.textContaining('18221261-78fa-4d84-9c40-f70b2a3c4d5e'), findsNWidgets(2)); // AppBar and Hero card
        expect(find.text('Uploaded to SORYNTH Server'), findsOneWidget);
      });
    });

    group('Startup Navigation, Back Navigation & Active SOS Resumption', () {
      testWidgets(
          'SplashScreen navigates guest user to AppRoutes.guestSos even when activeEmergencyId is stored',
          (WidgetTester tester) async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        await storage.setOnboardingCompleted(true);
        await storage.saveActiveEmergencyId('3ca5461c-b829');

        final fakeSupabase = FakeSyncSupabaseService();
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: true);
        final fakeBle = FakeSyncBluetoothService();
        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        String? currentNavigatedRoute;
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SplashScreen(),
            ),
            GoRoute(
              path: AppRoutes.guestSos,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.guestSos;
                return const Scaffold(body: Text('Guest SOS Screen'));
              },
            ),
            GoRoute(
              path: AppRoutes.sosActive,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.sosActive;
                return const Scaffold(body: Text('Sos Active Screen'));
              },
            ),
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.home;
                return const Scaffold(body: Text('Home Screen'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              offlineStorageServiceProvider.overrideWithValue(storage),
              supabaseServiceProvider.overrideWithValue(fakeSupabase),
              emergencyRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );

        // Advance past splash delay (2600ms)
        await tester.pump(const Duration(milliseconds: 2700));
        await tester.pumpAndSettle();

        // Must land on guestSos, NOT sosActive!
        expect(currentNavigatedRoute, equals(AppRoutes.guestSos));
        expect(find.text('Guest SOS Screen'), findsOneWidget);
        expect(find.text('Sos Active Screen'), findsNothing);
      });

      testWidgets(
          'SosActiveScreen visible back button routes to AppRoutes.guestSos for guest alerts when canPop is false',
          (WidgetTester tester) async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService();
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: true);
        final fakeBle = FakeSyncBluetoothService();
        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        final guestEmergency = EmergencyModel(
          emergencyId: 'SOR_GUEST_BACK',
          personId: '',
          personName: 'Civilian Guest',
          latitude: 12.9716,
          longitude: 77.5946,
          emergencyType: EmergencyType.medical,
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.uploadedToServer,
          timestamp: DateTime.now(),
          isGuest: true,
        );

        String? currentNavigatedRoute;
        final router = GoRouter(
          initialLocation: AppRoutes.sosActive,
          routes: [
            GoRoute(
              path: AppRoutes.sosActive,
              builder: (context, state) =>
                  SosActiveScreen(initialEmergency: guestEmergency),
            ),
            GoRoute(
              path: AppRoutes.guestSos,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.guestSos;
                return const Scaffold(body: Text('Guest SOS Screen'));
              },
            ),
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.home;
                return const Scaffold(body: Text('Home Screen'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              offlineStorageServiceProvider.overrideWithValue(storage),
              supabaseServiceProvider.overrideWithValue(fakeSupabase),
              emergencyRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify visible back button with tooltip 'Back' and icon
        final backBtn = find.byTooltip('Back');
        expect(backBtn, findsOneWidget);

        // Tap visible back button
        await tester.tap(backBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Navigates to Guest SOS, not Home
        expect(currentNavigatedRoute, equals(AppRoutes.guestSos));
        expect(find.text('Guest SOS Screen'), findsOneWidget);
      });

      testWidgets(
          'SosActiveScreen PopScope intercepts Android system back and routes to AppRoutes.guestSos without app exit',
          (WidgetTester tester) async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService();
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: true);
        final fakeBle = FakeSyncBluetoothService();
        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        final guestEmergency = EmergencyModel(
          emergencyId: 'SOR_GUEST_SYSBACK',
          personId: '',
          personName: 'Civilian Guest',
          latitude: 12.9716,
          longitude: 77.5946,
          emergencyType: EmergencyType.medical,
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.uploadedToServer,
          timestamp: DateTime.now(),
          isGuest: true,
        );

        String? currentNavigatedRoute;
        final router = GoRouter(
          initialLocation: AppRoutes.sosActive,
          routes: [
            GoRoute(
              path: AppRoutes.sosActive,
              builder: (context, state) =>
                  SosActiveScreen(initialEmergency: guestEmergency),
            ),
            GoRoute(
              path: AppRoutes.guestSos,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.guestSos;
                return const Scaffold(body: Text('Guest SOS Screen'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              offlineStorageServiceProvider.overrideWithValue(storage),
              supabaseServiceProvider.overrideWithValue(fakeSupabase),
              emergencyRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Simulate Android system back button dispatch
        final didPop = await tester.binding.handlePopRoute();
        expect(didPop, isTrue); // PopScope intercepted the system back event!
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Intercepted and gracefully navigated to Guest SOS
        expect(currentNavigatedRoute, equals(AppRoutes.guestSos));
        expect(find.text('Guest SOS Screen'), findsOneWidget);
      });

      testWidgets(
          'GuestSosScreen renders Active SOS resume banner when active emergency exists and tapping it navigates to AppRoutes.sosActive',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final activeEmergency = EmergencyModel(
          emergencyId: 'SOR_ACTIVE_RESUME',
          personId: '',
          personName: 'Civilian Guest',
          latitude: 12.9716,
          longitude: 77.5946,
          emergencyType: EmergencyType.medical,
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.queuedLocally,
          timestamp: DateTime.now(),
          isGuest: true,
        );
        await storage.saveEmergency(activeEmergency);
        await storage.saveActiveEmergencyId(activeEmergency.emergencyId);

        final fakeSupabase = FakeSyncSupabaseService();
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: false);
        final fakeBle = FakeSyncBluetoothService();
        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        String? currentNavigatedRoute;
        final router = GoRouter(
          initialLocation: AppRoutes.guestSos,
          routes: [
            GoRoute(
              path: AppRoutes.guestSos,
              builder: (context, state) => const GuestSosScreen(),
            ),
            GoRoute(
              path: AppRoutes.sosActive,
              builder: (context, state) {
                currentNavigatedRoute = AppRoutes.sosActive;
                return const Scaffold(body: Text('Sos Active Screen'));
              },
            ),
            GoRoute(
              path: AppRoutes.welcome,
              builder: (context, state) => const Scaffold(body: Text('Welcome Screen')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              offlineStorageServiceProvider.overrideWithValue(storage),
              supabaseServiceProvider.overrideWithValue(fakeSupabase),
              emergencyRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Resume banner is rendered with active SOS ID
        expect(find.text('ACTIVE SOS: SOR_ACTIVE_RESUME'), findsOneWidget);
        expect(find.textContaining('Tap to view tracking & telemetry'), findsOneWidget);

        // 2. Tapping the resume banner navigates to sosActive
        await tester.tap(find.text('ACTIVE SOS: SOR_ACTIVE_RESUME'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(currentNavigatedRoute, equals(AppRoutes.sosActive));
        expect(find.text('Sos Active Screen'), findsOneWidget);
      });
    });

    group('SOS Transmission-Source Integrity & Hardware Verification Specification', () {
      test('Offline pending SOS with no connected ESP32 is queued as INTERNET and NOT bluetoothLora', () async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: false);
        final fakeBle = FakeSyncBluetoothService(); // Disconnected

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        final emergency = EmergencyModel(
          emergencyId: 'SOR_TEST_OFFLINE_01',
          personId: 'CIVILIAN_OFFLINE',
          personName: 'Rohan Sharma',
          latitude: 12.9716,
          longitude: 77.5946,
          accuracy: 14.0,
          emergencyType: EmergencyType.medical,
          message: 'Medical SOS while offline',
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.queuedLocally,
          timestamp: DateTime.now(),
        );

        List<SosTransmissionStep> finalSteps = [];
        EmergencyModel? updated;
        await for (final steps in repo.dispatchEmergency(
          emergency: emergency,
          onEmergencyUpdated: (em) => updated = em,
        )) {
          finalSteps = steps;
        }

        // Verify Step 4 (Internet) skipped due to offline mode, and Step 5 (BLE) failed
        expect(finalSteps[3].isCompleted, isFalse);
        expect(finalSteps[3].detail, contains('Offline mode active'));
        expect(finalSteps[4].isFailed, isTrue);
        expect(finalSteps[4].detail, contains('No physical SORYNTH ESP32 connected via BLE'));

        // Verify emergency saved to local storage is QUEUED_LOCALLY
        final stored = storage.getEmergencyById('SOR_TEST_OFFLINE_01');
        expect(stored, isNotNull);
        expect(stored!.status, equals(EmergencyStatus.queuedLocally));
        expect(stored.wasQueuedOffline, isTrue);

        // CRITICAL CHECK: Must NOT be labeled as bluetoothLora!
        expect(stored.communicationMethod, equals(CommunicationMethod.internet));
        expect(stored.communicationMethod, isNot(equals(CommunicationMethod.bluetoothLora)));
        expect(updated?.communicationMethod, equals(CommunicationMethod.internet));
      });

      test('Wi-Fi restored: Pending offline SOS auto-syncs to Supabase as INTERNET (Cellular / Cloud)', () async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: false);
        final fakeBle = FakeSyncBluetoothService();

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        // 1. Dispatch offline emergency (No Wi-Fi, No ESP32)
        final emergency = EmergencyModel(
          emergencyId: 'SOR_TEST_AUTOSYNC_02',
          personId: 'CIVILIAN_AUTOSYNC',
          personName: 'Priya Patel',
          latitude: 13.0827,
          longitude: 80.2707,
          accuracy: 10.0,
          emergencyType: EmergencyType.accident,
          message: 'Vehicle breakdown in remote sector',
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.queuedLocally,
          timestamp: DateTime.now(),
        );

        await for (final _ in repo.dispatchEmergency(
          emergency: emergency,
          onEmergencyUpdated: (_) {},
        )) {}

        // Confirm alert is pending in local storage
        expect(storage.getPendingEmergencies().length, 1);
        expect(fakeSupabase.submitCallCount, 0);

        // 2. Wi-Fi is restored!
        fakeConnectivity.hasReachability = true;

        // 3. Auto-sync triggers
        await repo.syncPendingEmergencies();

        // 4. Verify Supabase submission
        expect(fakeSupabase.submitCallCount, 1);
        expect(fakeSupabase.lastSubmitted, isNotNull);
        expect(fakeSupabase.lastSubmitted!.emergencyId, equals('SOR_TEST_AUTOSYNC_02'));

        // CRITICAL TRANSMISSION SOURCE VERIFICATION:
        // Must be submitted with CommunicationMethod.internet ('INTERNET')
        // and NEVER falsely labeled as 'BLUETOOTH_LORA' or 'LORA_RELAY'!
        expect(fakeSupabase.lastSubmitted!.communicationMethod, equals(CommunicationMethod.internet));
        expect(fakeSupabase.lastSubmitted!.communicationMethod.code, equals('INTERNET'));
        expect(fakeSupabase.lastSubmitted!.communicationMethod, isNot(equals(CommunicationMethod.bluetoothLora)));
        expect(fakeSupabase.lastSubmitted!.communicationMethod, isNot(equals(CommunicationMethod.loraRelay)));

        // 5. Verify local storage record is updated to UPLOADED_TO_SERVER with internet method
        final synced = storage.getEmergencyById('SOR_TEST_AUTOSYNC_02');
        expect(synced, isNotNull);
        expect(synced!.status, equals(EmergencyStatus.uploadedToServer));
        expect(synced.communicationMethod, equals(CommunicationMethod.internet));
        expect(synced.isServerConfirmed, isTrue);
        expect(storage.getPendingEmergencies().isEmpty, isTrue);
      });

      test('Confirmed Physical ESP32 BLE Hardware ACK records BLUETOOTH_LORA', () async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: false);

        final ackBleResult = BleTransmissionResult(
          isSuccess: true,
          emergencyId: 'SOR_BLE_ACK_03',
          finalStatus: EmergencyStatus.gatewayReceived,
          hopCount: 1,
          relayNodes: const ['ESP32_NODE_GATEWAY'],
          isSimulated: false,
          message: 'Verified LoRa ACK received from physical ESP32 gateway.',
        );

        final bleService = FakeHardwareAckBluetoothService(ackBleResult);

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: bleService,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        final emergency = EmergencyModel(
          emergencyId: 'SOR_BLE_ACK_03',
          personId: 'CIVILIAN_BLE_ACK',
          personName: 'Amit Verma',
          latitude: 15.3647,
          longitude: 75.1240,
          accuracy: 8.0,
          emergencyType: EmergencyType.naturalDisaster,
          message: 'Flood water rising near bridge',
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.queuedLocally,
          timestamp: DateTime.now(),
        );

        EmergencyModel? updated;
        await for (final _ in repo.dispatchEmergency(
          emergency: emergency,
          onEmergencyUpdated: (em) => updated = em,
        )) {}

        // Confirmed direct hardware ACK (hopCount = 1) -> BLUETOOTH_LORA
        expect(updated?.communicationMethod, equals(CommunicationMethod.bluetoothLora));
        expect(updated?.status, equals(EmergencyStatus.gatewayReceived));
        expect(updated?.hopCount, equals(1));

        final stored = storage.getEmergencyById('SOR_BLE_ACK_03');
        expect(stored?.communicationMethod, equals(CommunicationMethod.bluetoothLora));
        expect(stored?.status, equals(EmergencyStatus.gatewayReceived));
      });

      test('Confirmed LoRa Mesh Relay Hardware ACK records LORA_RELAY', () async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: false);

        final meshBleResult = BleTransmissionResult(
          isSuccess: true,
          emergencyId: 'SOR_MESH_ACK_04',
          finalStatus: EmergencyStatus.relayReceived,
          hopCount: 3,
          relayNodes: const ['ESP32_RELAY_1', 'ESP32_RELAY_2', 'ESP32_GW'],
          isSimulated: false,
          message: 'Verified LoRa Mesh multi-hop ACK.',
        );

        final bleService = FakeHardwareAckBluetoothService(meshBleResult);

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: bleService,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        final emergency = EmergencyModel(
          emergencyId: 'SOR_MESH_ACK_04',
          personId: 'CIVILIAN_MESH_ACK',
          personName: 'Deepa Roy',
          latitude: 22.5726,
          longitude: 88.3639,
          accuracy: 6.0,
          emergencyType: EmergencyType.fire,
          message: 'Industrial warehouse fire',
          communicationMethod: CommunicationMethod.internet,
          status: EmergencyStatus.queuedLocally,
          timestamp: DateTime.now(),
        );

        EmergencyModel? updated;
        await for (final _ in repo.dispatchEmergency(
          emergency: emergency,
          onEmergencyUpdated: (em) => updated = em,
        )) {}

        // Confirmed multi-hop LoRa mesh ACK -> LORA_RELAY
        expect(updated?.communicationMethod, equals(CommunicationMethod.loraRelay));
        expect(updated?.status, equals(EmergencyStatus.relayReceived));
        expect(updated?.hopCount, equals(3));
        expect(updated?.relayPath, equals(['ESP32_RELAY_1', 'ESP32_RELAY_2', 'ESP32_GW']));

        final stored = storage.getEmergencyById('SOR_MESH_ACK_04');
        expect(stored?.communicationMethod, equals(CommunicationMethod.loraRelay));
        expect(stored?.status, equals(EmergencyStatus.relayReceived));
      });

      test('Sanitizes legacy offline alert with stale bluetoothLora method upon internet auto-sync', () async {
        final prefs = await SharedPreferences.getInstance();
        final storage = OfflineStorageService(prefs);
        final fakeSupabase = FakeSyncSupabaseService(shouldSucceed: true);
        final fakeConnectivity = FakeSyncConnectivityService(hasReachability: true);
        final fakeBle = FakeSyncBluetoothService();

        final repo = EmergencyRepository(
          supabaseService: fakeSupabase,
          bluetoothService: fakeBle,
          connectivityService: fakeConnectivity,
          storageService: storage,
        );

        // Simulate pre-existing alert saved before bug fix with queuedLocally but stale bluetoothLora
        final staleEmergency = EmergencyModel(
          emergencyId: 'SOR_LEGACY_STALE_05',
          personId: 'LEGACY_CIVILIAN',
          personName: 'Anil Kumar',
          latitude: 19.0760,
          longitude: 72.8777,
          accuracy: 12.0,
          emergencyType: EmergencyType.medical,
          message: 'Legacy offline alert needing sync',
          communicationMethod: CommunicationMethod.bluetoothLora, // Old bug saved this
          status: EmergencyStatus.queuedLocally, // No hardware ACK was ever received
          timestamp: DateTime.now(),
        );
        await storage.saveEmergency(staleEmergency);

        // Auto-sync executes over internet
        await repo.syncPendingEmergencies();

        // Must override stale method and submit as INTERNET
        expect(fakeSupabase.submitCallCount, 1);
        expect(fakeSupabase.lastSubmitted?.communicationMethod, equals(CommunicationMethod.internet));
        expect(fakeSupabase.lastSubmitted?.communicationMethod.code, equals('INTERNET'));

        final synced = storage.getEmergencyById('SOR_LEGACY_STALE_05');
        expect(synced?.communicationMethod, equals(CommunicationMethod.internet));
        expect(synced?.status, equals(EmergencyStatus.uploadedToServer));
      });
    });
  });
}
