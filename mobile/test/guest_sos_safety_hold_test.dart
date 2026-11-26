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
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';

// Test doubles to prevent real network/hardware calls
class FakeTestConnectivityService extends ConnectivityService {
  FakeTestConnectivityService() : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async => false;
}

class FakeTestBluetoothService implements BluetoothService {
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
      message: 'Test mock: offline queue',
    );
  }

  @override
  void dispose() {}
}

class FakeTestSupabaseService extends SupabaseService {
  @override
  bool get isConfigured => false;

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

  Widget buildGuestSosApp({required GoRouter router, required EmergencyRepository repo, required OfflineStorageService storage}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineStorageServiceProvider.overrideWithValue(storage),
        supabaseServiceProvider.overrideWithValue(FakeTestSupabaseService()),
        emergencyRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  GoRouter createTestRouter(List<EmergencyModel> capturedDispatches) {
    return GoRouter(
      initialLocation: AppRoutes.guestSos,
      routes: [
        GoRoute(
          path: AppRoutes.guestSos,
          builder: (context, state) => const GuestSosScreen(),
        ),
        GoRoute(
          path: AppRoutes.sosSending,
          builder: (context, state) {
            final emergency = state.extra as EmergencyModel?;
            if (emergency != null) {
              capturedDispatches.add(emergency);
            }
            return Scaffold(
              body: Center(
                child: Text('SOS Sending Screen Target: ${emergency?.emergencyId}'),
              ),
            );
          },
        ),
      ],
    );
  }

  group('GuestSosScreen SOS Press-and-Hold Safety Tests', () {
    testWidgets('1. Short tap does not trigger SOS', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeTestSupabaseService();
      final fakeBle = FakeTestBluetoothService();
      final fakeConn = FakeTestConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final capturedDispatches = <EmergencyModel>[];
      final router = createTestRouter(capturedDispatches);

      await tester.pumpWidget(
        buildGuestSosApp(router: router, repo: repo, storage: storage),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Perform a normal short tap
      await tester.tap(sosButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify that short tap NEVER triggers SOS
      expect(capturedDispatches, isEmpty);
      expect(find.textContaining('SOS Sending Screen Target'), findsNothing);
      expect(find.byType(GuestSosScreen), findsOneWidget);
    });

    testWidgets('2. Hold for less than 1500ms does not trigger SOS', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeTestSupabaseService();
      final fakeBle = FakeTestBluetoothService();
      final fakeConn = FakeTestConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final capturedDispatches = <EmergencyModel>[];
      final router = createTestRouter(capturedDispatches);

      await tester.pumpWidget(
        buildGuestSosApp(router: router, repo: repo, storage: storage),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Hold for 800ms (less than 1500ms safety threshold)
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 800));

      // Release early
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify NO SOS dispatch occurred
      expect(capturedDispatches, isEmpty);
      expect(find.textContaining('SOS Sending Screen Target'), findsNothing);
      expect(find.byType(GuestSosScreen), findsOneWidget);
    });

    testWidgets('3. Successful 1500ms hold triggers exactly once', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeTestSupabaseService();
      final fakeBle = FakeTestBluetoothService();
      final fakeConn = FakeTestConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final capturedDispatches = <EmergencyModel>[];
      final router = createTestRouter(capturedDispatches);

      await tester.pumpWidget(
        buildGuestSosApp(router: router, repo: repo, storage: storage),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Hold for full 1500ms duration (allowing 100ms for kPressTimeout)
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 150)); // kPressTimeout triggers onTapDown
      await tester.pump(const Duration(milliseconds: 1600)); // hold past 1500ms
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify triggered exactly once
      expect(capturedDispatches.length, equals(1));
      expect(capturedDispatches.first.emergencyId, startsWith('SOR'));
      expect(capturedDispatches.first.isGuest, isTrue);
      expect(find.textContaining('SOS Sending Screen Target'), findsOneWidget);
    });

    testWidgets('4. Releasing cancels the hold', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeTestSupabaseService();
      final fakeBle = FakeTestBluetoothService();
      final fakeConn = FakeTestConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final capturedDispatches = <EmergencyModel>[];
      final router = createTestRouter(capturedDispatches);

      await tester.pumpWidget(
        buildGuestSosApp(router: router, repo: repo, storage: storage),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Begin holding
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 500));

      // Verify UI shows active holding state
      expect(find.text('HOLDING...'), findsOneWidget);
      expect(find.text('Keep holding to broadcast...'), findsOneWidget);

      // Release finger before 1500ms completes
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify hold was cancelled and UI reverted to resting state
      expect(find.text('HOLDING...'), findsNothing);
      expect(find.text('HOLD 1.5s'), findsOneWidget);
      expect(find.text('Press & hold to activate alert'), findsOneWidget);
      expect(capturedDispatches, isEmpty);
    });

    testWidgets('5. Button remains visible on a 320px-wide screen without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeTestSupabaseService();
      final fakeBle = FakeTestBluetoothService();
      final fakeConn = FakeTestConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final capturedDispatches = <EmergencyModel>[];
      final router = createTestRouter(capturedDispatches);

      await tester.pumpWidget(
        buildGuestSosApp(router: router, repo: repo, storage: storage),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Verify button boundaries are strictly inside the 320x600 viewport
      final rect = tester.getRect(sosButtonFinder);
      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(rect.right, lessThanOrEqualTo(320.0));
      expect(rect.top, greaterThanOrEqualTo(0.0));
      expect(rect.bottom, lessThanOrEqualTo(600.0));

      // Ensure no exceptions (e.g. RenderFlex overflows) were thrown
      expect(tester.takeException(), isNull);
    });
  });
}
