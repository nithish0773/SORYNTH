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
import 'package:sorynth/features/emergency/sos_sending_screen.dart';
import 'package:sorynth/features/history/history_screen.dart';
import 'package:sorynth/features/home/home_screen.dart';
import 'package:sorynth/features/welcome/welcome_screen.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =============================================================================
// TEST DOUBLES FOR AUDIT SPECIFICATION
// =============================================================================

class AuditMockSupabaseService extends SupabaseService {
  bool isConfiguredValue;
  User? mockUser;
  bool resendCalled = false;
  String? lastResentEmail;
  bool throwUnconfirmedOnSignIn;
  bool throwConfiguredError;

  AuditMockSupabaseService({
    this.isConfiguredValue = true,
    this.mockUser,
    this.throwUnconfirmedOnSignIn = false,
    this.throwConfiguredError = false,
  });

  @override
  bool get isConfigured => isConfiguredValue;

  @override
  User? get currentUser => mockUser;

  @override
  Future<AuthResponse?> signIn({
    required String email,
    required String password,
  }) async {
    if (!isConfiguredValue || throwConfiguredError) {
      throw Exception('Authentication service is currently unavailable.');
    }
    if (throwUnconfirmedOnSignIn) {
      throw const AuthException(
        'Email not confirmed',
        statusCode: '400',
        code: 'email_not_confirmed',
      );
    }
    return AuthResponse(
      user: User(
        id: 'test-user-id',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      ),
      session: Session(
        accessToken: 'token-abc',
        tokenType: 'bearer',
        user: User(
          id: 'test-user-id',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01',
        ),
      ),
    );
  }

  @override
  Future<void> resendConfirmationEmail(
    String email, {
    String? emailRedirectTo,
  }) async {
    if (!isConfiguredValue) {
      throw Exception('Supabase backend is not configured.');
    }
    resendCalled = true;
    lastResentEmail = email;
  }

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    return UserProfile(
      id: userId,
      fullName: 'Civilian Responder',
      email: 'civilian@sorynth.org',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

class AuditMockBluetoothService implements BluetoothService {
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

class AuditMockConnectivityService extends ConnectivityService {
  bool hasReachability;
  AuditMockConnectivityService({this.hasReachability = false})
      : super(initialize: false);

  @override
  Future<bool> checkActualInternetReachability() async => hasReachability;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('A. Navigation & Guest SOS Flow', () {
    testWidgets(
        'SosSendingScreen abort by Guest User navigates to AppRoutes.guestSos, NOT AppRoutes.home',
        (WidgetTester tester) async {
      final storage = OfflineStorageService(prefs);
      final fakeSupabase = AuditMockSupabaseService(mockUser: null); // Guest (no login)
      final fakeBle = AuditMockBluetoothService();
      final fakeConn = AuditMockConnectivityService(hasReachability: false);
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final guestEmergency = EmergencyModel(
        emergencyId: 'SOR_GUEST_ABORT_1',
        personId: '',
        personName: 'Guest Civilian',
        latitude: 12.9716,
        longitude: 77.5946,
        emergencyType: EmergencyType.medical,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: DateTime.now(),
        isGuest: true,
      );
      await storage.saveEmergency(guestEmergency);

      String? currentRoute;
      final router = GoRouter(
        initialLocation: AppRoutes.sosSending,
        routes: [
          GoRoute(
            path: AppRoutes.sosSending,
            builder: (context, state) =>
                SosSendingScreen(emergency: guestEmergency),
          ),
          GoRoute(
            path: AppRoutes.guestSos,
            builder: (context, state) {
              currentRoute = AppRoutes.guestSos;
              return const Scaffold(body: Text('Guest SOS Screen'));
            },
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) {
              currentRoute = AppRoutes.home;
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
      await tester.pump(const Duration(milliseconds: 300));

      // Tap 'Abort' button in AppBar
      final abortBtn = find.text('Abort');
      expect(abortBtn, findsOneWidget);
      await tester.tap(abortBtn);
      await tester.pumpAndSettle();

      // Confirm abort dialog
      expect(find.text('Cancel Emergency Transmission?'), findsOneWidget);
      final confirmBtn = find.text('Cancel Alert');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Must navigate to Guest SOS, NEVER Home!
      expect(currentRoute, equals(AppRoutes.guestSos));
      expect(find.text('Guest SOS Screen'), findsOneWidget);
      expect(find.text('Home Screen'), findsNothing);
    });

    testWidgets(
        'LoginScreen leading back button navigates to AppRoutes.welcome when canPop is false',
        (WidgetTester tester) async {
      final fakeSupabase = AuditMockSupabaseService();

      String? currentRoute;
      final router = GoRouter(
        initialLocation: AppRoutes.login,
        routes: [
          GoRoute(
            path: AppRoutes.login,
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: AppRoutes.welcome,
            builder: (context, state) {
              currentRoute = AppRoutes.welcome;
              return const Scaffold(body: Text('Welcome Screen'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap leading back button
      final backBtn = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      expect(currentRoute, equals(AppRoutes.welcome));
      expect(find.text('Welcome Screen'), findsOneWidget);
    });

    testWidgets(
        'LoginScreen PopScope intercepts Android system back button and returns to AppRoutes.welcome without app exit',
        (WidgetTester tester) async {
      final fakeSupabase = AuditMockSupabaseService();

      String? currentRoute;
      final router = GoRouter(
        initialLocation: AppRoutes.login,
        routes: [
          GoRoute(
            path: AppRoutes.login,
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: AppRoutes.welcome,
            builder: (context, state) {
              currentRoute = AppRoutes.welcome;
              return const Scaffold(body: Text('Welcome Screen'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate Android back gesture/button
      final didPop = await tester.binding.handlePopRoute();
      expect(didPop, isTrue); // PopScope intercepted
      await tester.pumpAndSettle();

      expect(currentRoute, equals(AppRoutes.welcome));
      expect(find.text('Welcome Screen'), findsOneWidget);
    });
  });

  group('B. Authentication & Unconfirmed Email Handling', () {
    testWidgets(
        'LoginScreen detects unconfirmed email error and displays Resend Verification Email action',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeSupabase = AuditMockSupabaseService(
        throwUnconfirmedOnSignIn: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
          ],
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter credentials
      final emailField = find.widgetWithText(TextFormField, 'Enter Email Address');
      final passField = find.byType(TextFormField).at(1);

      await tester.enterText(emailField, 'unconfirmed@sorynth.org');
      await tester.enterText(passField, 'password123');

      // Tap Sign In
      final signInBtn = find.widgetWithText(ElevatedButton, 'Sign In');
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      // Verify friendly unconfirmed email message
      expect(
        find.textContaining('Your email address has not been confirmed yet'),
        findsOneWidget,
      );

      // Verify 'Resend Verification Email' button is displayed
      final resendBtn = find.text('Resend Verification Email');
      expect(resendBtn, findsOneWidget);

      // Tap 'Resend Verification Email'
      await tester.tap(resendBtn);
      await tester.pumpAndSettle();

      // Verify service was invoked with the exact email
      expect(fakeSupabase.resendCalled, isTrue);
      expect(fakeSupabase.lastResentEmail, equals('unconfirmed@sorynth.org'));

      // Verify user confirmation feedback
      expect(
        find.textContaining('Verification email resent! Please check your inbox'),
        findsOneWidget,
      );
    });
  });

  group('G. Responsive UI & Overflow Protection (320px Display)', () {
    testWidgets(
        'HomeScreen active emergency banner does not overflow on 320px narrow display with long UUID',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = AuditMockSupabaseService(
        mockUser: const User(
          id: 'user-narrow-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01',
        ),
      );
      final fakeBle = AuditMockBluetoothService();
      final fakeConn = AuditMockConnectivityService(hasReachability: false);
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final longUuidEmergency = EmergencyModel(
        emergencyId: '18221261-78fa-4d84-9c40-f70b2a3c4d5e',
        personId: 'user-narrow-1',
        personName: 'Civilian Responder',
        latitude: 12.9716,
        longitude: 77.5946,
        emergencyType: EmergencyType.medical,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime.now(),
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
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('18221261-78fa-4d84-9c40-f70b2a3c4d5e'), findsWidgets);
    });

    testWidgets(
        'HomeScreen history mini card does not overflow on 320px narrow display with long UUID',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = AuditMockSupabaseService(
        mockUser: const User(
          id: 'user-narrow-2',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01',
        ),
      );
      final fakeBle = AuditMockBluetoothService();
      final fakeConn = AuditMockConnectivityService(hasReachability: false);
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final longUuidEmergency = EmergencyModel(
        emergencyId: '3ca5461c-b829-4f81-a672-91d1e4e2098b',
        personId: 'user-narrow-2',
        personName: 'Civilian Responder',
        latitude: 12.9716,
        longitude: 77.5946,
        emergencyType: EmergencyType.accident,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.resolved,
        timestamp: DateTime.now(),
      );
      await storage.saveEmergency(longUuidEmergency);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            emergencyRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('3ca5461c-b829-4f81-a672-91d1e4e2098b'), findsOneWidget);
    });

    testWidgets(
        'HistoryScreen does not overflow on 320px narrow display with long UUID cards',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = AuditMockSupabaseService();
      final fakeBle = AuditMockBluetoothService();
      final fakeConn = AuditMockConnectivityService(hasReachability: false);
      final repo = EmergencyRepository(
        supabaseService: fakeSupabase,
        bluetoothService: fakeBle,
        connectivityService: fakeConn,
        storageService: storage,
      );

      final longUuidEmergency = EmergencyModel(
        emergencyId: '18221261-78fa-4d84-9c40-f70b2a3c4d5e',
        personId: 'civilian-history-1',
        personName: 'Civilian Responder',
        latitude: 12.9716,
        longitude: 77.5946,
        emergencyType: EmergencyType.naturalDisaster,
        communicationMethod: CommunicationMethod.bluetoothLora,
        status: EmergencyStatus.uploadedToServer,
        timestamp: DateTime.now(),
      );
      await storage.saveEmergency(longUuidEmergency);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            offlineStorageServiceProvider.overrideWithValue(storage),
            supabaseServiceProvider.overrideWithValue(fakeSupabase),
            emergencyRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: HistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('18221261-78fa-4d84-9c40-f70b2a3c4d5e'), findsOneWidget);
    });

    testWidgets('WelcomeScreen smoothly adapts to constrained screen height without overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('EMERGENCY SOS'), findsOneWidget);
      expect(find.text('Sign In to Account'), findsOneWidget);
    });

    testWidgets(
        'GuestSosScreen renders SOS button within visible viewport on small Android display without scrolling',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final storage = OfflineStorageService(prefs);
      final fakeSupabase = AuditMockSupabaseService();
      final fakeBle = AuditMockBluetoothService();
      final fakeConn = AuditMockConnectivityService(hasReachability: false);
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
            path: AppRoutes.welcome,
            builder: (context, state) => const Scaffold(body: Text('Welcome')),
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
      await tester.pump(const Duration(milliseconds: 300));

      final buttonFinder = find.byType(SosButton);
      expect(buttonFinder, findsOneWidget);

      final rect = tester.getRect(buttonFinder);
      expect(rect.top, greaterThanOrEqualTo(0.0));
      expect(rect.bottom, lessThanOrEqualTo(640.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('F. GPS & Location Resilience', () {
    test('GpsResult accurately reflects failure state and unavailable coordinates', () {
      final failure = GpsResult.failure(
        message: 'Location permission was denied.',
        isPermissionDenied: true,
      );

      expect(failure.isSuccess, isFalse);
      expect(failure.isPermissionDenied, isTrue);
      expect(failure.quality, equals(GpsQuality.unavailable));
      expect(failure.qualityBadgeLabel, equals('GPS Fix Unavailable'));

      final emergency = EmergencyModel(
        emergencyId: 'SOR_GPS_FAIL_1',
        personId: '',
        personName: 'Civilian',
        latitude: failure.latitude,
        longitude: failure.longitude,
        accuracy: null,
        emergencyType: EmergencyType.medical,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.queuedLocally,
        timestamp: failure.timestamp,
      );

      expect(emergency.hasValidCoordinates, isFalse);
      expect(emergency.coordinatesFormatted, equals('Location Unavailable'));
      expect(emergency.accuracyFormatted, equals('Location Unavailable'));
    });
  });
}
