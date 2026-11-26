import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_constants.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/core/routing/app_router.dart';
import 'package:sorynth/data/models/emergency_model.dart';
import 'package:sorynth/data/repositories/emergency_repository.dart';
import 'package:sorynth/data/services/bluetooth_service.dart';
import 'package:sorynth/data/services/connectivity_service.dart';
import 'package:sorynth/data/services/offline_storage_service.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/home/home_screen.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';

class MockLifecycleSupabaseService extends SupabaseService {
  bool shouldSucceed = true;
  int submitCount = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<Map<String, dynamic>> submitSosAlert(EmergencyModel emergency) async {
    submitCount++;
    if (shouldSucceed) {
      return {
        'success': true,
        'emergency_id': emergency.emergencyId,
        'status': 'REGISTERED',
      };
    } else {
      throw Exception('503 Service Unavailable');
    }
  }
}

class MockLifecycleConnectivityService extends ConnectivityService {
  final bool hasInternet;

  MockLifecycleConnectivityService({this.hasInternet = true})
      : super(initialize: false);

  @override
  bool get isOnline => hasInternet;

  @override
  Future<bool> checkActualInternetReachability() async => hasInternet;

  @override
  Stream<bool> get onConnectivityChanged => Stream.value(hasInternet);
}

class MockLifecycleBluetoothService implements BluetoothService {
  final _telemetryController = StreamController<BleTelemetry>.broadcast();
  final BleTelemetry _telemetry = const BleTelemetry(
    status: BleConnectionStatus.disconnected,
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
  Future<bool> isBluetoothSupportedAndEnabled() async => false;
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 4)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> connectToNode(String deviceId) async => false;
  @override
  Future<void> disconnect() async {}
  @override
  Future<BleTransmissionResult> transmitEmergencyPacket(
    EmergencyModel emergency, {
    void Function(String progressStep)? onProgress,
  }) async {
    return BleTransmissionResult(
      isSuccess: false,
      emergencyId: emergency.emergencyId,
      finalStatus: EmergencyStatus.queuedLocally,
      isSimulated: true,
      message: 'Mock disconnected',
    );
  }

  @override
  void dispose() {
    _telemetryController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  EmergencyModel createSampleEmergency(String id, EmergencyStatus status) {
    return EmergencyModel(
      emergencyId: id,
      personId: 'test-person',
      personName: 'Test Civilian',
      phone: '+1234567890',
      latitude: 12.9716,
      longitude: 77.5946,
      accuracy: 12.0,
      emergencyType: EmergencyType.medical,
      message: 'Medical Assistance Required',
      communicationMethod: CommunicationMethod.internet,
      status: status,
      timestamp: DateTime.now(),
    );
  }

  group('A. Single Consistent isGenuinelyActive Definition', () {
    test('Identifies active vs inactive terminal statuses correctly', () {
      final activeStatuses = [
        EmergencyStatus.gpsAcquiring,
        EmergencyStatus.gpsLocked,
        EmergencyStatus.queuedLocally,
        EmergencyStatus.connectingToEsp32,
        EmergencyStatus.transmittingViaLora,
        EmergencyStatus.relayReceived,
        EmergencyStatus.gatewayReceived,
        EmergencyStatus.rescueTeamAcknowledged,
        EmergencyStatus.inAction,
        EmergencyStatus.failed,
      ];

      for (final st in activeStatuses) {
        final em = createSampleEmergency('TEST-ACT', st);
        expect(em.isGenuinelyActive, isTrue,
            reason: '${st.code} must be considered genuinely active');
      }

      final inactiveTerminalStatuses = [
        EmergencyStatus.uploadedToServer,
        EmergencyStatus.resolved,
        EmergencyStatus.cancelled,
      ];

      for (final st in inactiveTerminalStatuses) {
        final em = createSampleEmergency('TEST-INACT', st);
        expect(em.isGenuinelyActive, isFalse,
            reason: '${st.code} must NOT be considered genuinely active');
      }
    });

    test('rescueTeamAcknowledged is handled safely and does not hide an emergency requiring action', () {
      final ackEmergency = createSampleEmergency('SOR-RESCUE-ACK', EmergencyStatus.rescueTeamAcknowledged);
      expect(ackEmergency.isGenuinelyActive, isTrue,
          reason: 'rescueTeamAcknowledged must remain active because the rescue mission requires ongoing action');
      expect(ackEmergency.isServerConfirmed, isTrue,
          reason: 'rescueTeamAcknowledged is verified server confirmed');
    });
  });

  group('B. Active Emergency Lifecycle, Storage & Notifier Synchronization', () {
    test('App restart: Stale synced/cancelled alerts (like SOR950081) are cleared on load', () async {
      final storage = OfflineStorageService(prefs);
      // Simulate stale SOR950081 with status UPLOADED_TO_SERVER in storage
      final staleAlert = createSampleEmergency('SOR950081', EmergencyStatus.uploadedToServer);
      await storage.saveEmergency(staleAlert);
      await storage.saveActiveEmergencyId('SOR950081');

      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      final notifier = ActiveEmergencyNotifier(repo);

      // Notifier state must be null!
      expect(notifier.state, isNull);
      // Stale active ID must be cleared from storage!
      expect(storage.getActiveEmergencyId(), isNull);
      // Emergency history is strictly preserved (never deleted!)
      expect(storage.getEmergencyById('SOR950081'), isNotNull);
      expect(storage.getAllEmergencies().length, equals(1));
    });

    test('App restart: Genuinely active alert is restored on startup', () async {
      final storage = OfflineStorageService(prefs);
      final activeAlert = createSampleEmergency('SOR777777', EmergencyStatus.queuedLocally);
      await storage.saveEmergency(activeAlert);
      await storage.saveActiveEmergencyId('SOR777777');

      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      final notifier = ActiveEmergencyNotifier(repo);

      expect(notifier.state, isNotNull);
      expect(notifier.state!.emergencyId, equals('SOR777777'));
      expect(storage.getActiveEmergencyId(), equals('SOR777777'));
    });

    test('Successful sync: Clears active emergency from storage and sets notifier to null', () async {
      final storage = OfflineStorageService(prefs);
      final activeAlert = createSampleEmergency('SOR_SYNC_OK', EmergencyStatus.queuedLocally);
      await storage.saveEmergency(activeAlert);
      await storage.saveActiveEmergencyId('SOR_SYNC_OK');

      final fakeSupabase = MockLifecycleSupabaseService()..shouldSucceed = true;
      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: fakeSupabase,
        connectivityService: MockLifecycleConnectivityService(hasInternet: true),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      final notifier = ActiveEmergencyNotifier(repo);
      expect(notifier.state, isNotNull);

      // Run sync
      await repo.syncPendingEmergencies();
      await Future<void>.delayed(Duration.zero);

      // State becomes null
      expect(notifier.state, isNull);
      // Active ID is cleared
      expect(storage.getActiveEmergencyId(), isNull);
      // Record is preserved in storage as UPLOADED_TO_SERVER
      final stored = storage.getEmergencyById('SOR_SYNC_OK');
      expect(stored, isNotNull);
      expect(stored!.status, equals(EmergencyStatus.uploadedToServer));
    });

    test('Failed sync: Keeps active emergency intact and pending', () async {
      final storage = OfflineStorageService(prefs);
      final activeAlert = createSampleEmergency('SOR_SYNC_FAIL', EmergencyStatus.queuedLocally);
      await storage.saveEmergency(activeAlert);
      await storage.saveActiveEmergencyId('SOR_SYNC_FAIL');

      final fakeSupabase = MockLifecycleSupabaseService()..shouldSucceed = false;
      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: fakeSupabase,
        connectivityService: MockLifecycleConnectivityService(hasInternet: true),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      final notifier = ActiveEmergencyNotifier(repo);
      expect(notifier.state, isNotNull);

      // Run sync (which fails)
      await repo.syncPendingEmergencies();

      // Active state must NOT be cleared because delivery failed
      expect(notifier.state, isNotNull);
      expect(notifier.state!.emergencyId, equals('SOR_SYNC_FAIL'));
      expect(storage.getActiveEmergencyId(), equals('SOR_SYNC_FAIL'));
      expect(storage.getEmergencyById('SOR_SYNC_FAIL')!.status,
          equals(EmergencyStatus.queuedLocally));
    });

    test('Cancellation: Stand down SOS clears active session', () async {
      final storage = OfflineStorageService(prefs);
      final activeAlert = createSampleEmergency('SOR_CANCEL_ME', EmergencyStatus.queuedLocally);
      await storage.saveEmergency(activeAlert);
      await storage.saveActiveEmergencyId('SOR_CANCEL_ME');

      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      final notifier = ActiveEmergencyNotifier(repo);
      expect(notifier.state, isNotNull);

      await notifier.cancelActive();

      expect(notifier.state, isNull);
      expect(storage.getActiveEmergencyId(), isNull);
      expect(storage.getEmergencyById('SOR_CANCEL_ME')!.status,
          equals(EmergencyStatus.cancelled));
    });

    test('Resolution: Resolving mission clears active session', () async {
      final storage = OfflineStorageService(prefs);
      final activeAlert = createSampleEmergency('SOR_RESOLVE_ME', EmergencyStatus.queuedLocally);
      await storage.saveEmergency(activeAlert);
      await storage.saveActiveEmergencyId('SOR_RESOLVE_ME');

      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      final notifier = ActiveEmergencyNotifier(repo);
      expect(notifier.state, isNotNull);

      await repo.resolveEmergency('SOR_RESOLVE_ME');
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isNull);
      expect(storage.getActiveEmergencyId(), isNull);
      expect(storage.getEmergencyById('SOR_RESOLVE_ME')!.status,
          equals(EmergencyStatus.resolved));
    });
  });

  group('C. UI Presentation: Home SOS Button & Active SOS Card', () {
    Widget createHomeScreenWidget({
      required EmergencyRepository repo,
    }) {
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.guestSos,
            builder: (context, state) => const GuestSosScreen(),
          ),
          GoRoute(
            path: AppRoutes.sosActive,
            builder: (context, state) =>
                const Scaffold(body: Text('Active Tracking Screen')),
          ),
          GoRoute(
            path: AppRoutes.emergencyTypes,
            builder: (context, state) =>
                const Scaffold(body: Text('Emergency Types Screen')),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const Scaffold(body: Text('Profile')),
          ),
          GoRoute(
            path: AppRoutes.history,
            builder: (context, state) => const Scaffold(body: Text('History')),
          ),
        ],
      );

      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          emergencyRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      );
    }

    testWidgets('HomeScreen renders enlarged 260px SOS button that navigates directly on tap without hold delay',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      await tester.pumpWidget(createHomeScreenWidget(repo: repo));
      await tester.pumpAndSettle();

      // Verify SOS Button exists and is configured for 1.5s emergency hold
      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      final sosWidget = tester.widget<SosButton>(sosButtonFinder);
      expect(sosWidget.holdDuration, equals(const Duration(milliseconds: 1500)));

      // Verify labels
      expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
      expect(find.text('HOLD 1.5s'), findsOneWidget);
      expect(find.text('Press & hold to activate alert'), findsOneWidget);
      expect(find.text('Select Emergency Category'), findsOneWidget);
    });

    testWidgets('Active SOS card displays for genuinely active emergency and wraps on 320px screen without overflow',
        (WidgetTester tester) async {
      // Constrained 320px narrow mobile viewport
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final activeEmergency =
          createSampleEmergency('SOR999111', EmergencyStatus.queuedLocally);
      await storage.saveEmergency(activeEmergency);
      await storage.saveActiveEmergencyId('SOR999111');

      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      await tester.pumpWidget(createHomeScreenWidget(repo: repo));
      await tester.pumpAndSettle();

      // Verify card is rendered
      expect(find.text('ACTIVE SOS: SOR999111'), findsOneWidget);
      expect(find.byType(Wrap), findsWidgets);

      // Ensure no overflow exception was thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets('Active SOS card does NOT render if emergency was already synced (uploadedToServer)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      // Emergency is synced
      final syncedEmergency =
          createSampleEmergency('SOR950081', EmergencyStatus.uploadedToServer);
      await storage.saveEmergency(syncedEmergency);
      // Attempting to set stale active ID
      await storage.saveActiveEmergencyId('SOR950081');

      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: MockLifecycleSupabaseService(),
        connectivityService: MockLifecycleConnectivityService(hasInternet: false),
        bluetoothService: MockLifecycleBluetoothService(),
      );

      await tester.pumpWidget(createHomeScreenWidget(repo: repo));
      await tester.pumpAndSettle();

      // Card must NOT be displayed
      expect(find.text('ACTIVE SOS: SOR950081'), findsNothing);
    });
  });
}
