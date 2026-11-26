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
import 'package:sorynth/data/services/connectivity_service.dart';
import 'package:sorynth/data/services/device_readiness_service.dart';
import 'package:sorynth/data/services/offline_storage_service.dart';
import 'package:sorynth/data/services/settings_service.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/profile/profile_screen.dart';
import 'package:sorynth/features/readiness/device_readiness_screen.dart';
import 'package:sorynth/features/settings/settings_screen.dart';
import 'package:sorynth/features/splash/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockProfileSupabaseService extends SupabaseService {
  User? _mockUser;
  int signOutCallCount = 0;

  MockProfileSupabaseService({User? initialUser}) : _mockUser = initialUser;

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _mockUser;

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _mockUser = null;
  }
}

class FakeDeviceReadinessService extends DeviceReadinessService {
  final ServiceReadiness mockBluetooth;
  final ServiceReadiness mockLocation;
  final ServiceReadiness mockInternet;

  FakeDeviceReadinessService({
    required super.connectivity,
    this.mockBluetooth = const ServiceReadiness(
      status: ServiceReadinessStatus.ready,
      title: 'Bluetooth BLE Mesh Ready',
      description: 'Ready to pair',
      actionLabel: 'Ready',
      icon: Icons.bluetooth_connected_rounded,
    ),
    this.mockLocation = const ServiceReadiness(
      status: ServiceReadinessStatus.ready,
      title: 'GPS & Location Ready',
      description: 'Coordinates available',
      actionLabel: 'Ready',
      icon: Icons.my_location_rounded,
    ),
    this.mockInternet = const ServiceReadiness(
      status: ServiceReadinessStatus.ready,
      title: 'Internet Connected',
      description: 'Connected via Wi-Fi',
      actionLabel: 'Connected',
      icon: Icons.wifi_rounded,
    ),
  });

  @override
  Future<ServiceReadiness> checkBluetooth() async => mockBluetooth;

  @override
  Future<ServiceReadiness> checkLocation() async => mockLocation;

  @override
  Future<ServiceReadiness> checkInternet() async => mockInternet;

  @override
  Future<DeviceReadinessState> checkAll() async {
    return DeviceReadinessState(
      bluetooth: mockBluetooth,
      location: mockLocation,
      internet: mockInternet,
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

  const authenticatedUser = User(
    id: 'usr-9948201-abc',
    appMetadata: {'provider': 'google'},
    userMetadata: {
      'full_name': 'Chief Responder Jane Doe',
    },
    aud: 'authenticated',
    createdAt: '2025-08-15T10:30:00Z',
    email: 'jane.doe@rescue.org',
    emailConfirmedAt: '2025-08-15T11:00:00Z',
  );

  Widget createTestWidget({
    required Widget child,
    MockProfileSupabaseService? supabase,
    UserProfile? profile,
    DeviceReadinessService? readinessService,
    String initialLocation = AppRoutes.profile,
  }) {
    final sb = supabase ?? MockProfileSupabaseService();
    final connectivity = ConnectivityService();

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (context, state) => child,
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('Login Screen Mock')),
        ),
        GoRoute(
          path: AppRoutes.history,
          builder: (context, state) => const Scaffold(body: Text('History Screen Mock')),
        ),
        GoRoute(
          path: AppRoutes.guestSos,
          builder: (context, state) => const Scaffold(body: Text('Guest SOS Screen Mock')),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('Home Screen Mock')),
        ),
        GoRoute(
          path: AppRoutes.deviceReadiness,
          builder: (context, state) => const DeviceReadinessScreen(),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseServiceProvider.overrideWithValue(sb),
        connectivityServiceProvider.overrideWithValue(connectivity),
        if (readinessService != null)
          deviceReadinessServiceProvider.overrideWithValue(readinessService),
        if (profile != null)
          userProfileProvider.overrideWith((ref) {
            final notifier = UserProfileNotifier(sb);
            notifier.state = profile;
            return notifier;
          }),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    );
  }

  group('Profile Screen & Account Safety Tests', () {
    testWidgets('Authenticated user sees display name, email, UID, provider, and Logout',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSupabase = MockProfileSupabaseService(initialUser: authenticatedUser);
      final profile = UserProfile(
        id: authenticatedUser.id,
        fullName: 'Chief Responder Jane Doe',
        email: authenticatedUser.email,
        bloodGroup: 'O+',
        createdAt: DateTime.parse(authenticatedUser.createdAt),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(createTestWidget(
        child: const ProfileScreen(),
        supabase: fakeSupabase,
        profile: profile,
      ));
      await tester.pumpAndSettle();

      // Verify user display name & email
      expect(find.text('Chief Responder Jane Doe'), findsWidgets);
      expect(find.text('jane.doe@rescue.org'), findsOneWidget);

      // Verify Account Details card
      expect(find.text('Account Details'), findsOneWidget);
      expect(find.text('GOOGLE'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);

      // Verify Settings navigation option
      expect(find.text('Settings & System Preferences'), findsOneWidget);

      // Verify Logout button exists for authenticated user
      final logoutButton = find.widgetWithText(OutlinedButton, 'Log Out from Account');
      expect(logoutButton, findsOneWidget);
    });

    testWidgets('Guest user sees guest session notice and does NOT see Account Details or Logout',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Supabase has null currentUser (guest)
      final fakeSupabase = MockProfileSupabaseService(initialUser: null);

      await tester.pumpWidget(createTestWidget(
        child: const ProfileScreen(),
        supabase: fakeSupabase,
      ));
      await tester.pumpAndSettle();

      // Guest banner is visible
      expect(find.text('Guest Emergency Session'), findsOneWidget);
      expect(find.text('Sign In / Register Account'), findsOneWidget);

      // Authenticated Account Details card is NOT rendered
      expect(find.text('Account Details'), findsNothing);
      expect(find.text('User ID (UID)'), findsNothing);
      expect(find.text('Member Since'), findsNothing);

      // Logout button is NOT rendered for guests
      expect(find.widgetWithText(OutlinedButton, 'Log Out from Account'), findsNothing);

      // Settings navigation is still accessible
      expect(find.text('Settings & System Preferences'), findsOneWidget);
    });

    testWidgets('Tapping Logout shows safe confirmation dialog with Cancel and Log Out',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSupabase = MockProfileSupabaseService(initialUser: authenticatedUser);

      await tester.pumpWidget(createTestWidget(
        child: const ProfileScreen(),
        supabase: fakeSupabase,
      ));
      await tester.pumpAndSettle();

      final logoutButton = find.widgetWithText(OutlinedButton, 'Log Out from Account');
      await tester.ensureVisible(logoutButton);
      await tester.tap(logoutButton);
      await tester.pumpAndSettle();

      // Verify dialog appears
      expect(find.text('Log Out from SORYNTH?'), findsOneWidget);
      expect(
        find.textContaining('Your offline emergency records, pending transmissions'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Log Out'), findsOneWidget);

      // Tap Cancel -> stays on Profile
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Log Out from SORYNTH?'), findsNothing);
      expect(fakeSupabase.signOutCallCount, equals(0));
    });

    testWidgets('Confirming Logout preserves offline records and navigates to Login',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storageService = OfflineStorageService(prefs);

      // Seed pending emergency and active emergency ID
      final testEmergency = EmergencyModel(
        emergencyId: 'SOR-PENDING-77',
        personId: 'usr-9948201-abc',
        personName: 'Chief Jane',
        emergencyType: EmergencyType.medical,
        status: EmergencyStatus.pending,
        communicationMethod: CommunicationMethod.internet,
        latitude: 12.9716,
        longitude: 77.5946,
        timestamp: DateTime.now(),
        message: 'Critical SOS before logout',
      );
      await storageService.saveEmergency(testEmergency);
      await storageService.saveActiveEmergencyId('SOR-PENDING-77');

      // Verify seeded records exist before logout
      expect(storageService.getPendingEmergencies().length, equals(1));
      expect(storageService.getActiveEmergencyId(), equals('SOR-PENDING-77'));

      final fakeSupabase = MockProfileSupabaseService(initialUser: authenticatedUser);

      await tester.pumpWidget(createTestWidget(
        child: const ProfileScreen(),
        supabase: fakeSupabase,
      ));
      await tester.pumpAndSettle();

      final logoutButton = find.widgetWithText(OutlinedButton, 'Log Out from Account');
      await tester.ensureVisible(logoutButton);
      await tester.tap(logoutButton);
      await tester.pumpAndSettle();

      // Tap Log Out in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log Out'));
      await tester.pumpAndSettle();

      // Verify signOut was dispatched
      expect(fakeSupabase.signOutCallCount, equals(1));

      // CRITICAL SAFETY CHECK: Verify pending records and active emergency ID were NEVER wiped
      expect(storageService.getPendingEmergencies().length, equals(1));
      expect(storageService.getPendingEmergencies().first.emergencyId, equals('SOR-PENDING-77'));
      expect(storageService.getActiveEmergencyId(), equals('SOR-PENDING-77'));

      // Verify navigated to Login screen
      expect(find.text('Login Screen Mock'), findsOneWidget);
    });

    testWidgets('Tapping Settings tile in ProfileScreen navigates to SettingsScreen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSupabase = MockProfileSupabaseService(initialUser: authenticatedUser);

      await tester.pumpWidget(createTestWidget(
        child: const ProfileScreen(),
        supabase: fakeSupabase,
      ));
      await tester.pumpAndSettle();

      final settingsTile = find.text('Settings & System Preferences');
      await tester.ensureVisible(settingsTile);
      await tester.tap(settingsTile);
      await tester.pumpAndSettle();

      // Verify we arrived at SettingsScreen
      expect(find.text('Notifications & Emergency Alerts'), findsOneWidget);
      expect(find.text('Emergency & Hardware Diagnostics'), findsOneWidget);
      expect(find.text('App Preferences & About'), findsOneWidget);
    });
  });

  group('Settings Screen Functionality & Persistence Tests', () {
    testWidgets('SettingsScreen allows toggling theme and persists in SettingsService',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(
        child: const SettingsScreen(),
        initialLocation: AppRoutes.settings,
      ));
      await tester.pumpAndSettle();

      // Initial theme mode is system
      final settingsService = SettingsService(prefs);
      expect(settingsService.loadSettings().themeMode, equals(ThemeMode.system));

      // Tap Dark Theme segment
      final darkButton = find.text('Dark');
      await tester.ensureVisible(darkButton);
      await tester.tap(darkButton);
      await tester.pumpAndSettle();

      // Verify persisted theme mode changed to dark
      expect(settingsService.loadSettings().themeMode, equals(ThemeMode.dark));

      // Tap Light Theme segment
      final lightButton = find.text('Light');
      await tester.ensureVisible(lightButton);
      await tester.tap(lightButton);
      await tester.pumpAndSettle();

      // Verify persisted theme mode changed to light
      expect(settingsService.loadSettings().themeMode, equals(ThemeMode.light));
    });

    testWidgets('Disabling SOS status notification prompts safety warning confirmation',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(
        child: const SettingsScreen(),
        initialLocation: AppRoutes.settings,
      ));
      await tester.pumpAndSettle();

      // Find the SOS Status Alerts switch tile
      final switchFinder = find.widgetWithText(SwitchListTile, 'SOS Status Alerts');
      expect(switchFinder, findsOneWidget);
      await tester.ensureVisible(switchFinder);

      // Tap to toggle off
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Verify safety warning dialog is displayed
      expect(find.text('Safety Warning'), findsOneWidget);
      expect(
        find.textContaining('Disabling SOS notifications may prevent you from seeing real-time confirmation'),
        findsOneWidget,
      );

      // Tap Keep Enabled
      await tester.tap(find.widgetWithText(TextButton, 'Keep Enabled'));
      await tester.pumpAndSettle();

      // Setting remains true (not disabled)
      final settingsService = SettingsService(prefs);
      expect(settingsService.loadSettings().sosStatusNotificationsEnabled, isTrue);
    });

    testWidgets('Settings dialogs (About, Help, Privacy) open correctly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget(
        child: const SettingsScreen(),
        initialLocation: AppRoutes.settings,
      ));
      await tester.pumpAndSettle();

      // Test About SORYNTH dialog
      final aboutTile = find.text('About SORYNTH');
      await tester.ensureVisible(aboutTile);
      await tester.tap(aboutTile);
      await tester.pumpAndSettle();

      expect(find.text('SORYNTH'), findsWidgets);
      expect(find.text('Close'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Test Help & Emergency Support dialog
      final helpTile = find.text('Help & Emergency Support');
      await tester.ensureVisible(helpTile);
      await tester.tap(helpTile);
      await tester.pumpAndSettle();

      expect(find.text('Help & Emergency Support'), findsWidgets);
      expect(find.text('Close'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Test Civilian Privacy Policy dialog
      final privacyTile = find.text('Privacy & Civilian Data Safety');
      await tester.ensureVisible(privacyTile);
      await tester.tap(privacyTile);
      await tester.pumpAndSettle();

      expect(find.text('Privacy & Civilian Data Safety'), findsWidgets);
      expect(find.text('Understood'), findsOneWidget);
      await tester.tap(find.text('Understood'));
      await tester.pumpAndSettle();
    });
  });

  group('Device Readiness Screen Tests', () {
    testWidgets('Renders status cards and allows continuing in offline mode',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connectivity = ConnectivityService();
      final fakeReadinessService = FakeDeviceReadinessService(
        connectivity: connectivity,
        mockBluetooth: const ServiceReadiness(
          status: ServiceReadinessStatus.disabled,
          title: 'Bluetooth is Disabled',
          description: 'Turn ON Bluetooth to communicate with remote ESP32 LoRa mesh transceivers.',
          actionLabel: 'Turn ON Bluetooth',
          icon: Icons.bluetooth_disabled_rounded,
        ),
        mockLocation: const ServiceReadiness(
          status: ServiceReadinessStatus.ready,
          title: 'GPS & Location Ready',
          description: 'High-accuracy satellite coordinates available.',
          actionLabel: 'Ready',
          icon: Icons.my_location_rounded,
        ),
        mockInternet: const ServiceReadiness(
          status: ServiceReadinessStatus.disabled,
          title: 'No Active Internet Connection',
          description: 'SORYNTH will transmit alerts via offline ESP32 LoRa radio mesh.',
          actionLabel: 'Connect Network',
          icon: Icons.wifi_off_rounded,
        ),
      );

      await tester.pumpWidget(createTestWidget(
        child: const DeviceReadinessScreen(),
        readinessService: fakeReadinessService,
        initialLocation: AppRoutes.deviceReadiness,
      ));
      await tester.pumpAndSettle();

      // Status cards are visible
      expect(find.text('Pre-Flight Safety Check'), findsOneWidget);
      expect(find.text('Bluetooth is Disabled'), findsOneWidget);
      expect(find.text('GPS & Location Ready'), findsOneWidget);
      expect(find.text('No Active Internet Connection'), findsOneWidget);

      // Button shows Continue in Offline Mode
      final continueButton = find.text('Continue in Offline Mode');
      expect(continueButton, findsOneWidget);

      // Guest SOS emergency bypass is always available
      expect(find.text('Guest SOS'), findsOneWidget);
    });

    testWidgets('Guest SOS bypass in Device Readiness AppBar navigates without permission blockage',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final connectivity = ConnectivityService();
      final fakeReadinessService = FakeDeviceReadinessService(
        connectivity: connectivity,
        mockLocation: const ServiceReadiness(
          status: ServiceReadinessStatus.permissionRequired,
          title: 'Location Permission Needed',
          description: 'Location access required',
          actionLabel: 'Grant Permission',
          icon: Icons.location_searching_rounded,
        ),
      );

      await tester.pumpWidget(createTestWidget(
        child: const DeviceReadinessScreen(),
        readinessService: fakeReadinessService,
        initialLocation: AppRoutes.deviceReadiness,
      ));
      await tester.pumpAndSettle();

      // Tap Guest SOS emergency bypass in AppBar
      final guestSosButton = find.widgetWithText(TextButton, 'Guest SOS');
      expect(guestSosButton, findsOneWidget);
      await tester.tap(guestSosButton);
      await tester.pumpAndSettle();

      // Navigated to Guest SOS without being blocked
      expect(find.text('Guest SOS Screen Mock'), findsOneWidget);
    });
  });

  group('Startup Navigation Sequence Tests', () {
    testWidgets('SplashScreen routes to DeviceReadinessScreen when device has readiness issues',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = OfflineStorageService(prefs);
      await storage.setOnboardingCompleted(true);

      final connectivity = ConnectivityService();
      final fakeReadinessService = FakeDeviceReadinessService(
        connectivity: connectivity,
        mockBluetooth: const ServiceReadiness(
          status: ServiceReadinessStatus.disabled,
          title: 'Bluetooth is Disabled',
          description: 'Turn ON Bluetooth to communicate with remote ESP32 LoRa mesh transceivers.',
          actionLabel: 'Turn ON Bluetooth',
          icon: Icons.bluetooth_disabled_rounded,
        ),
      );

      await tester.pumpWidget(createTestWidget(
        child: const SplashScreen(),
        readinessService: fakeReadinessService,
        initialLocation: AppRoutes.splash,
      ));

      // Advance through splash delay (2600ms + extra pump)
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pumpAndSettle();

      // Verify routed to Device Readiness
      expect(find.text('Pre-Flight Safety Check'), findsOneWidget);
      expect(find.text('Bluetooth is Disabled'), findsOneWidget);
    });

    testWidgets('SplashScreen routes to Home when device is ready and user is authenticated',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = OfflineStorageService(prefs);
      await storage.setOnboardingCompleted(true);

      final connectivity = ConnectivityService();
      final fakeReadinessService = FakeDeviceReadinessService(
        connectivity: connectivity,
        // All services ready by default in FakeDeviceReadinessService
      );

      final fakeSupabase = MockProfileSupabaseService(initialUser: authenticatedUser);

      await tester.pumpWidget(createTestWidget(
        child: const SplashScreen(),
        readinessService: fakeReadinessService,
        supabase: fakeSupabase,
        initialLocation: AppRoutes.splash,
      ));

      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pumpAndSettle();

      // Verify routed directly to Home
      expect(find.text('Home Screen Mock'), findsOneWidget);
    });

    testWidgets('SplashScreen routes to Guest SOS when device is ready and user is unauthenticated',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = OfflineStorageService(prefs);
      await storage.setOnboardingCompleted(true);

      final connectivity = ConnectivityService();
      final fakeReadinessService = FakeDeviceReadinessService(
        connectivity: connectivity,
        // All services ready by default
      );

      // Unauthenticated
      final fakeSupabase = MockProfileSupabaseService(initialUser: null);

      await tester.pumpWidget(createTestWidget(
        child: const SplashScreen(),
        readinessService: fakeReadinessService,
        supabase: fakeSupabase,
        initialLocation: AppRoutes.splash,
      ));

      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pumpAndSettle();

      // Verify routed to Guest SOS
      expect(find.text('Guest SOS Screen Mock'), findsOneWidget);
    });
  });
}
