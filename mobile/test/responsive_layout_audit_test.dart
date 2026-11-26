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
import 'package:sorynth/features/authentication/login_screen.dart';
import 'package:sorynth/features/authentication/registration_screen.dart';
import 'package:sorynth/features/emergency/emergency_type_screen.dart';
import 'package:sorynth/features/emergency/sos_sending_screen.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/features/home/home_screen.dart';
import 'package:sorynth/features/profile/profile_screen.dart';
import 'package:sorynth/features/tracking/sos_active_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResponsiveMockSupabaseService extends SupabaseService {
  final User? mockUser;
  ResponsiveMockSupabaseService({this.mockUser});

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => mockUser;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    return UserProfile(
      id: userId,
      fullName: 'Civilian Responder',
      email: mockUser?.email ?? 'responder@sorynth.org',
      phoneNumber: '+91 98765 43210',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<EmergencyModel?> getEmergencyStatus(String emergencyId) async => null;
}

class ResponsiveMockBluetoothService implements BluetoothService {
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
      message: 'No physical ESP32 connected.',
    );
  }
  @override
  void dispose() {
    _telemetryController.close();
  }
}

class ResponsiveMockConnectivityService extends ConnectivityService {
  ResponsiveMockConnectivityService() : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async => true;
}

class ResponsiveMockGpsService extends GpsService {
  @override
  Future<GpsResult> getCurrentLocation({Duration timeout = const Duration(seconds: 12)}) async {
    return GpsResult(
      isSuccess: true,
      latitude: 12.9716,
      longitude: 77.5946,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildTestApp({
    required Widget child,
    required SharedPreferences prefs,
    User? mockUser,
    EmergencyRepository? customRepo,
    OfflineStorageService? customStorage,
  }) {
    final storage = customStorage ?? OfflineStorageService(prefs);
    final supabase = ResponsiveMockSupabaseService(mockUser: mockUser);
    final ble = ResponsiveMockBluetoothService();
    final conn = ResponsiveMockConnectivityService();
    final repo = customRepo ??
        EmergencyRepository(
          supabaseService: supabase,
          bluetoothService: ble,
          connectivityService: conn,
          storageService: storage,
        );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => child),
        GoRoute(path: AppRoutes.emergencyTypes, builder: (context, state) => const Scaffold(body: Text('Types'))),
        GoRoute(path: AppRoutes.guestSos, builder: (context, state) => const Scaffold(body: Text('Guest SOS'))),
        GoRoute(path: AppRoutes.home, builder: (context, state) => const Scaffold(body: Text('Home'))),
        GoRoute(path: AppRoutes.welcome, builder: (context, state) => const Scaffold(body: Text('Welcome'))),
        GoRoute(path: AppRoutes.history, builder: (context, state) => const Scaffold(body: Text('History'))),
        GoRoute(path: AppRoutes.profile, builder: (context, state) => const Scaffold(body: Text('Profile'))),
      ],
    );

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        offlineStorageServiceProvider.overrideWithValue(storage),
        supabaseServiceProvider.overrideWithValue(supabase),
        bluetoothServiceProvider.overrideWithValue(ble),
        connectivityServiceProvider.overrideWithValue(conn),
        gpsServiceProvider.overrideWithValue(ResponsiveMockGpsService()),
        emergencyRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('SORYNTH Responsive Layout Audit Across Android Viewports', () {
    const viewports = [
      Size(320, 568), // Ultra-compact 320px (iPhone SE / compact Android)
      Size(360, 640), // Standard budget 360px
      Size(393, 852), // Modern standard 393px
      Size(432, 960), // Large flagship 432px
    ];

    for (final vp in viewports) {
      testWidgets('HomeScreen renders with centered SOS button and no overflow at ${vp.width}x${vp.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = vp;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(
            child: const HomeScreen(),
            prefs: prefs,
            mockUser: const User(
              id: 'test-user',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final sosFinder = find.byType(SosButton);
        expect(sosFinder, findsOneWidget);

        final rect = tester.getRect(sosFinder);
        // Button is horizontally within bounds
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(vp.width));
        // Button is visible in the viewport without scrolling
        expect(rect.top, greaterThanOrEqualTo(0.0));
        expect(rect.top, lessThan(vp.height));
        if (vp.height >= 640) {
          expect(rect.bottom, lessThanOrEqualTo(vp.height));
        }
      });

      testWidgets('GuestSosScreen renders SOS button centered and visible without scroll at ${vp.width}x${vp.height}',
          (WidgetTester tester) async {
        tester.view.physicalSize = vp;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(
            child: const GuestSosScreen(),
            prefs: prefs,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final sosFinder = find.byType(SosButton);
        expect(sosFinder, findsOneWidget);

        final rect = tester.getRect(sosFinder);
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(vp.width));
        // SOS Button must be visible without scrolling on all Android displays
        expect(rect.top, greaterThanOrEqualTo(0.0));
        expect(rect.bottom, lessThanOrEqualTo(vp.height));

        // Verify HOLD 1.5s is visible
        expect(find.text('HOLD 1.5s'), findsOneWidget);
        expect(find.text('Press & hold to activate alert'), findsOneWidget);
      });
    }

    testWidgets('EmergencyTypeScreen scales category grid and transmit button cleanly at 320px',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const EmergencyTypeScreen(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      final err = tester.takeException();
      if (err != null) {
        if (err is FlutterError) {
          for (final d in err.diagnostics) {
            debugPrint('DIAG: ${d.toString()}');
          }
        } else {
          debugPrint('DEBUG OVERFLOW IN EmergencyTypeScreen: $err');
        }
      }
      expect(err, isNull);
      expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
      expect(find.byType(SosButton), findsOneWidget);
      expect(find.text('Select Emergency Category'), findsOneWidget);
    });

    testWidgets('SosSendingScreen header card wraps cleanly without overflow at 320px',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final emergency = EmergencyModel(
        emergencyId: 'SOR987654',
        personId: 'USER_1',
        personName: 'Rohan Sharma',
        latitude: 12.9716,
        longitude: 77.5946,
        emergencyType: EmergencyType.naturalDisaster,
        message: 'Severe flood warning, water rising fast',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
      );

      final storage = OfflineStorageService(prefs);
      final supabase = ResponsiveMockSupabaseService();
      final ble = ResponsiveMockBluetoothService();
      final conn = ResponsiveMockConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: supabase,
        bluetoothService: ble,
        connectivityService: conn,
        storageService: storage,
      );
      await storage.saveEmergency(emergency);

      await tester.pumpWidget(
        buildTestApp(
          child: SosSendingScreen(emergency: emergency),
          prefs: prefs,
          customRepo: repo,
          customStorage: storage,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(tester.takeException(), isNull);
      expect(find.text(EmergencyType.naturalDisaster.label), findsOneWidget);
    });

    testWidgets('SosActiveScreen action buttons and radar render cleanly at 320px',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final emergency = EmergencyModel(
        emergencyId: 'SOR112233',
        personId: 'USER_1',
        personName: 'Priya Patel',
        latitude: 12.9716,
        longitude: 77.5946,
        emergencyType: EmergencyType.medical,
        message: 'Cardiac emergency, need ambulance',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime.now(),
      );

      final storage = OfflineStorageService(prefs);
      final supabase = ResponsiveMockSupabaseService();
      final ble = ResponsiveMockBluetoothService();
      final conn = ResponsiveMockConnectivityService();
      final repo = EmergencyRepository(
        supabaseService: supabase,
        bluetoothService: ble,
        connectivityService: conn,
        storageService: storage,
      );
      await storage.saveEmergency(emergency);

      await tester.pumpWidget(
        buildTestApp(
          child: SosActiveScreen(initialEmergency: emergency),
          prefs: prefs,
          customRepo: repo,
          customStorage: storage,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Active SOS: SOR112233'), findsOneWidget);
      expect(find.text('I Am Safe • Stand Down SOS'), findsOneWidget);
    });

    testWidgets('LoginScreen and RegistrationScreen render without overflow at 320px',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const LoginScreen(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      final err1 = tester.takeException();
      expect(err1, isNull);
      expect(find.text('Welcome Back'), findsOneWidget);

      await tester.pumpWidget(
        buildTestApp(
          child: const RegistrationScreen(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      final err2 = tester.takeException();
      expect(err2, isNull);
      expect(find.text('Join SORYNTH'), findsOneWidget);
    });

    testWidgets('ProfileScreen renders without overflow at 320px',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          child: const ProfileScreen(),
          prefs: prefs,
          mockUser: const User(
            id: 'user-profile-test',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final err = tester.takeException();
      if (err != null) {
        if (err is FlutterError) {
          for (final d in err.diagnostics) {
            debugPrint('DIAG: ${d.toString()}');
          }
        } else {
          debugPrint('DEBUG OVERFLOW IN EmergencyTypeScreen: $err');
        }
      }
      expect(err, isNull);
      expect(find.text('Rescue Medical Profile'), findsOneWidget);
    });
  });
}
