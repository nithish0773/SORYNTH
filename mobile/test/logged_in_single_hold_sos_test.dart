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
import 'package:sorynth/data/models/user_profile.dart';
import 'package:sorynth/data/repositories/emergency_repository.dart';
import 'package:sorynth/data/services/bluetooth_service.dart';
import 'package:sorynth/data/services/connectivity_service.dart';
import 'package:sorynth/data/services/gps_service.dart';
import 'package:sorynth/data/services/offline_storage_service.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/emergency/emergency_type_screen.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/features/home/home_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGpsService extends GpsService {
  @override
  Future<GpsResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    return GpsResult(
      isSuccess: true,
      latitude: 13.0827,
      longitude: 80.2707,
      accuracy: 5.0,
      timestamp: DateTime.now(),
    );
  }
}

class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService() : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async => true;
}

class FakeBluetoothService implements BluetoothService {
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
      isSuccess: true,
      emergencyId: emergency.emergencyId,
      finalStatus: EmergencyStatus.pending,
      isSimulated: true,
      message: 'Simulated BLE transmission',
    );
  }

  @override
  void dispose() {
    _telemetryController.close();
  }
}

class FakeLoggedInSupabaseService extends SupabaseService {
  final User _mockUser = const User(
    id: 'user-auth-1234',
    appMetadata: {},
    userMetadata: {'full_name': 'Commander Shepherd'},
    aud: 'authenticated',
    createdAt: '2026-01-01',
    email: 'shepherd@normandy.org',
  );

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _mockUser;

  @override
  Future<Map<String, dynamic>> submitSosAlert(EmergencyModel emergency) async {
    return {'success': true, 'status': 'REGISTERED'};
  }
}

class FakeGuestSupabaseService extends SupabaseService {
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

  group('Direct Logged-In HomeScreen SOS Hold Flow Tests', () {
    testWidgets(
        '1. HomeScreen directly renders HOLD SOS control, category selection, and optional description without redundant tap button',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeLoggedInSupabaseService();
      final repo = EmergencyRepository(
        storageService: storage,
        supabaseService: fakeSupabase,
        connectivityService: FakeConnectivityService(),
        bluetoothService: FakeBluetoothService(),
      );

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
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
      await tester.pumpAndSettle();

      // Verify the HOLD SOS button is directly accessible on HomeScreen
      expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
      expect(find.text('Category: URGENT / UNSPECIFIED'), findsOneWidget);
      expect(find.byType(SosButton), findsOneWidget);

      // Verify redundant SELECT CATEGORY tap button is gone
      expect(find.text('SELECT CATEGORY'), findsNothing);
      expect(find.text('Tap to select category & hold SOS'), findsNothing);

      // Verify category selection and optional description exist directly on HomeScreen
      expect(find.text('Select Emergency Category'), findsOneWidget);
      expect(find.text('Situation & Victim Description'), findsOneWidget);
      expect(find.text('OPTIONAL'), findsOneWidget);
    });

    testWidgets(
        '2. HomeScreen direct 1.5s hold immediately transmits urgent SOS (Case 1: URGENT / UNSPECIFIED)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('SOS Transmission Pipeline'));
            },
          ),
        ],
      );

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeLoggedInSupabaseService();
      final userProfile = UserProfile(
        id: 'user-auth-1234',
        fullName: 'Commander Shepherd',
        phoneNumber: '+15551234567',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            gpsServiceProvider.overrideWithValue(MockGpsService()),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            userProfileProvider.overrideWith((ref) {
              final notifier = UserProfileNotifier(fakeSupabase);
              notifier.state = userProfile;
              return notifier;
            }),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);
      await tester.ensureVisible(sosButtonFinder);

      // Perform continuous 1.5s hold directly on HomeScreen
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1600));
      await gesture.up();
      await tester.pumpAndSettle();

      // Assert immediate dispatch to pipeline without intermediary screen
      expect(find.text('SOS Transmission Pipeline'), findsOneWidget);
      expect(capturedEmergencies.length, equals(1));
      expect(capturedEmergencies.first.personId, equals('user-auth-1234'));
      expect(capturedEmergencies.first.personName, equals('Commander Shepherd'));
      expect(capturedEmergencies.first.message, equals('Emergency Alert: URGENT / UNSPECIFIED'));
      expect(capturedEmergencies.first.isGuest, isFalse);
    });

    testWidgets(
        '3. HomeScreen categorized SOS with description (Case 2: Selected Category)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('SOS Transmission Pipeline'));
            },
          ),
        ],
      );

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeLoggedInSupabaseService();
      final userProfile = UserProfile(
        id: 'user-auth-1234',
        fullName: 'Commander Shepherd',
        phoneNumber: '+15551234567',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            gpsServiceProvider.overrideWithValue(MockGpsService()),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            userProfileProvider.overrideWith((ref) {
              final notifier = UserProfileNotifier(fakeSupabase);
              notifier.state = userProfile;
              return notifier;
            }),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Accident category directly on HomeScreen
      final accidentCard = find.text('Accident');
      await tester.ensureVisible(accidentCard);
      await tester.tap(accidentCard);
      await tester.pumpAndSettle();

      // Verify dynamic chip updates
      expect(find.text('Selected: Accident'), findsOneWidget);

      // Enter optional description directly on HomeScreen
      final descField = find.byType(TextField);
      await tester.ensureVisible(descField);
      await tester.enterText(descField, '2 car collision at junction, fuel leaking');
      await tester.pumpAndSettle();

      // Perform 1.5s hold on HomeScreen
      final sosButtonFinder = find.byType(SosButton);
      await tester.ensureVisible(sosButtonFinder);
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1600));
      await gesture.up();
      await tester.pumpAndSettle();

      // Assert dispatch with selected category and description
      expect(find.text('SOS Transmission Pipeline'), findsOneWidget);
      expect(capturedEmergencies.length, equals(1));
      expect(capturedEmergencies.first.emergencyType, equals(EmergencyType.accident));
      expect(capturedEmergencies.first.message, equals('2 car collision at junction, fuel leaking'));
    });

    testWidgets(
        '4. Releasing hold early (< 1.5s) on HomeScreen cancels transmission without alert creation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('SOS Transmission Pipeline'));
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
            gpsServiceProvider.overrideWithValue(MockGpsService()),
            supabaseServiceProvider.overrideWithValue(FakeLoggedInSupabaseService()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sosButtonFinder = find.byType(SosButton);
      await tester.ensureVisible(sosButtonFinder);

      // Start hold gesture and release at 600ms (< 1500ms)
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();

      // Assert transmission did not occur
      expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
      expect(find.text('SOS Transmission Pipeline'), findsNothing);
      expect(capturedEmergencies, isEmpty);
    });

    testWidgets(
        '5. Duplicate hold triggers/callbacks on HomeScreen cannot transmit multiple SOS alerts',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('SOS Transmission Pipeline'));
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
            gpsServiceProvider.overrideWithValue(MockGpsService()),
            supabaseServiceProvider.overrideWithValue(FakeLoggedInSupabaseService()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sosButtonFinder = find.byType(SosButton);
      final sosWidget = tester.widget<SosButton>(sosButtonFinder);

      // Trigger first hold completion callback
      sosWidget.onTriggered();
      // Immediately invoke duplicate callback while dispatching
      sosWidget.onTriggered();
      await tester.pumpAndSettle();

      // Exactly ONE emergency alert must be constructed and transmitted
      expect(capturedEmergencies.length, equals(1));
    });

    testWidgets(
        '6. EmergencyTypeScreen maintains route compatibility and initialType selection via shared LoggedInSosSection',
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
              return const Scaffold(body: Text('SOS Transmission Pipeline'));
            },
          ),
        ],
      );

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = FakeLoggedInSupabaseService();
      final userProfile = UserProfile(
        id: 'user-auth-1234',
        fullName: 'Commander Shepherd',
        phoneNumber: '+15551234567',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            gpsServiceProvider.overrideWithValue(MockGpsService()),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            userProfileProvider.overrideWith((ref) {
              final notifier = UserProfileNotifier(fakeSupabase);
              notifier.state = userProfile;
              return notifier;
            }),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AppBar is present on EmergencyTypeScreen
      expect(find.text('SOS Emergency Details'), findsOneWidget);

      // Verify Fire category is preselected from initialType
      expect(find.text('Selected: Fire'), findsOneWidget);

      // Perform 1.5s hold
      final sosButtonFinder = find.byType(SosButton);
      await tester.ensureVisible(sosButtonFinder);
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1600));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('SOS Transmission Pipeline'), findsOneWidget);
      expect(capturedEmergencies.length, equals(1));
      expect(capturedEmergencies.first.emergencyType, equals(EmergencyType.fire));
    });

    testWidgets(
        '7. Guest SOS hold behavior remains unchanged: single 1.5s hold transmits, tap does not transmit',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final capturedEmergencies = <EmergencyModel>[];

      final router = GoRouter(
        initialLocation: AppRoutes.guestSos,
        routes: [
          GoRoute(
            path: AppRoutes.guestSos,
            builder: (context, state) => const GuestSosScreen(),
          ),
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) {
              final em = state.extra as EmergencyModel?;
              if (em != null) {
                capturedEmergencies.add(em);
              }
              return const Scaffold(body: Text('Guest SOS Transmission Pipeline'));
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
            gpsServiceProvider.overrideWithValue(MockGpsService()),
            supabaseServiceProvider.overrideWithValue(FakeGuestSupabaseService()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sosButtonFinder = find.byType(SosButton);
      expect(sosButtonFinder, findsOneWidget);

      // Verify tap on guest screen does NOT transmit
      await tester.tap(sosButtonFinder);
      await tester.pumpAndSettle();
      expect(capturedEmergencies, isEmpty);

      // Verify 1.5s hold transmits
      final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 1600));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Guest SOS Transmission Pipeline'), findsOneWidget);
      expect(capturedEmergencies.length, equals(1));
      expect(capturedEmergencies.first.isGuest, isTrue);
    });
  });
}
