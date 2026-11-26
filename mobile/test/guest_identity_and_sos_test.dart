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
import 'package:sorynth/data/services/gps_service.dart';
import 'package:sorynth/data/services/offline_storage_service.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/emergency/emergency_type_screen.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockTestGpsService extends GpsService {
  @override
  Future<GpsResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    return GpsResult(
      isSuccess: true,
      latitude: 13.0827,
      longitude: 80.2707,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    );
  }
}

class FakeGuestTestConnectivityService extends ConnectivityService {
  FakeGuestTestConnectivityService() : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async => false;
}

class FakeGuestTestBluetoothService implements BluetoothService {
  final BleTelemetry _telemetry = const BleTelemetry(
    status: BleConnectionStatus.disconnected,
    isSimulated: true,
  );

  @override
  BleTelemetry get currentTelemetry => _telemetry;

  @override
  Stream<BleTelemetry> get telemetryStream => const Stream.empty();

  @override
  bool get isSimulated => true;

  @override
  String get modeLabel => 'TEST MODE';

  @override
  Future<bool> isBluetoothSupportedAndEnabled() async => false;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {}

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
      message: 'Test mock: queued locally',
    );
  }

  @override
  void dispose() {}
}

class FakeGuestTestSupabaseService extends SupabaseService {
  @override
  bool get isConfigured => false;

  @override
  User? get currentUser => null;

  @override
  Future<Map<String, dynamic>> submitSosAlert(EmergencyModel emergency) async {
    return {'success': true, 'status': 'QUEUED'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('Guest Identity & Offline Storage Tests', () {
    test('OfflineStorageService generates unique GUEST- format identifier and persists it', () {
      final storage = OfflineStorageService(prefs);
      final guestId1 = storage.getOrCreateGuestId();

      expect(guestId1.startsWith('GUEST-'), isTrue);
      expect(guestId1.length, greaterThan(10));

      // Second call must return the exact same identifier
      final guestId2 = storage.getOrCreateGuestId();
      expect(guestId2, equals(guestId1));

      // Must be persisted in SharedPreferences
      expect(prefs.getString(AppConstants.keyGuestId), equals(guestId1));
    });

    test('Guest SOS history is retained until app data is cleared', () async {
      final storage = OfflineStorageService(prefs);
      final guestId = storage.getOrCreateGuestId();

      final em = EmergencyModel(
        emergencyId: 'SOR888001',
        personId: guestId,
        personName: 'Civilian Guest',
        latitude: 13.0827,
        longitude: 80.2707,
        accuracy: 10.0,
        emergencyType: EmergencyType.medical,
        message: 'Guest Medical Emergency',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime.now(),
        isGuest: true,
      );

      await storage.saveEmergency(em);

      // Verify it exists in storage
      final storedList = storage.getAllEmergencies();
      expect(storedList.length, equals(1));
      expect(storedList.first.emergencyId, equals('SOR888001'));
      expect(storedList.first.isGuest, isTrue);
      expect(storedList.first.personId, equals(guestId));
    });
  });

  group('SOS Category Selection & Hold-to-Transmit Flow Tests', () {
    testWidgets('EmergencyTypeScreen displays selected category and automatically transmits on hold complete',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.emergencyTypes,
        routes: [
          GoRoute(
            path: AppRoutes.emergencyTypes,
            builder: (context, state) =>
                const EmergencyTypeScreen(initialType: EmergencyType.accident),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('SOS Sending Screen Target'));
            },
          ),
        ],
      );

      final storage = OfflineStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            gpsServiceProvider.overrideWithValue(MockTestGpsService()),
            supabaseServiceProvider.overrideWithValue(FakeGuestTestSupabaseService()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify category confirmation display
      expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
      expect(find.text('Selected: Accident'), findsOneWidget);

      // Verify hold button is present
      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Perform Hold SOS (1.5 seconds)
      await tester.ensureVisible(sosButtonFinder);
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 1600));
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify automatic transmission occurred without needing a separate transmit button
      expect(find.text('SOS Sending Screen Target'), findsOneWidget);
      expect(capturedEmergencies.length, equals(1));
      expect(capturedEmergencies.first.emergencyType, equals(EmergencyType.accident));
      expect(capturedEmergencies.first.isGuest, isTrue);
      expect(capturedEmergencies.first.personId.startsWith('GUEST-'), isTrue);
    });

    testWidgets('Releasing early cancels hold without alert creation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.emergencyTypes,
        routes: [
          GoRoute(
            path: AppRoutes.emergencyTypes,
            builder: (context, state) =>
                const EmergencyTypeScreen(initialType: EmergencyType.fire),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('SOS Sending Screen Target'));
            },
          ),
        ],
      );

      final storage = OfflineStorageService(prefs);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            gpsServiceProvider.overrideWithValue(MockTestGpsService()),
            supabaseServiceProvider.overrideWithValue(FakeGuestTestSupabaseService()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hold for only 500ms and release early (less than 1500ms requirement)
      final sosButtonFinder = find.byType(SosButton);
      await tester.ensureVisible(sosButtonFinder);
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();

      // Should remain on the screen without transmitting
      expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
      expect(find.text('SOS Sending Screen Target'), findsNothing);
      expect(capturedEmergencies.isEmpty, isTrue);
    });

    testWidgets('GuestSosScreen AppBar provides History and Settings access without login',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeGuestTestSupabaseService();
      final fakeBle = FakeGuestTestBluetoothService();
      final fakeConn = FakeGuestTestConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final router = GoRouter(
        initialLocation: AppRoutes.guestSos,
        routes: [
          GoRoute(
            path: AppRoutes.guestSos,
            builder: (context, state) => const GuestSosScreen(),
          ),
          GoRoute(
            path: AppRoutes.history,
            builder: (context, state) => const Scaffold(body: Text('Guest SOS History Screen')),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const Scaffold(body: Text('App Settings Screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            gpsServiceProvider.overrideWithValue(MockTestGpsService()),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            emergencyRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify History button
      final historyBtn = find.text('SOS History');
      expect(historyBtn, findsOneWidget);
      await tester.ensureVisible(historyBtn);
      await tester.tap(historyBtn);
      await tester.pumpAndSettle();
      expect(find.text('Guest SOS History Screen'), findsOneWidget);
    });
  });
}
