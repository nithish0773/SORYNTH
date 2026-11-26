import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_colors.dart';
import 'package:sorynth/core/constants/app_constants.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/core/routing/app_router.dart';
import 'package:sorynth/data/services/gps_service.dart';
import 'package:sorynth/features/emergency/emergency_type_screen.dart';
import 'package:sorynth/features/guest_sos/guest_sos_screen.dart';
import 'package:sorynth/features/home/home_screen.dart';
import 'package:sorynth/shared/widgets/sos_button.dart';
import 'package:sorynth/shared/widgets/sorynth_logo.dart';

class MockGpsService extends GpsService {
  @override
  Future<GpsResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    return GpsResult(
      isSuccess: true,
      latitude: 12.9716,
      longitude: 77.5946,
      accuracy: 10.0,
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

  Widget buildTestableWidget(
    Widget child, {
    GoRouter? router,
    SharedPreferences? mockPrefs,
  }) {
    final effectivePrefs = mockPrefs ?? prefs;
    final routerToUse = router ??
        GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => child,
            ),
            GoRoute(
              path: AppRoutes.sosSending,
              builder: (context, state) =>
                  const Scaffold(body: Text('SOS Sending Screen')),
            ),
          ],
        );

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(effectivePrefs),
        gpsServiceProvider.overrideWithValue(MockGpsService()),
      ],
      child: MaterialApp.router(
        routerConfig: routerToUse,
      ),
    );
  }

  testWidgets('EmergencyTypeScreen renders categories and multiline description field',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestableWidget(const EmergencyTypeScreen()),
    );
    await tester.pumpAndSettle();

    // Verify Title & Headers
    expect(find.text('SOS Emergency Details'), findsOneWidget);
    expect(find.text('Select Emergency Category'), findsOneWidget);
    expect(find.text('Situation & Victim Description'), findsOneWidget);

    // Verify all 6 emergency categories are rendered
    for (final type in EmergencyType.values) {
      expect(find.text(type.label), findsOneWidget);
    }

    // Verify prominent multiline description field and Hold SOS button
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(SosButton), findsOneWidget);
    expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
  });

  testWidgets('EmergencyTypeScreen preselects initialType when provided',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestableWidget(
        const EmergencyTypeScreen(initialType: EmergencyType.fire),
      ),
    );
    await tester.pumpAndSettle();

    // Fire category should have checkmark icon indicating selection
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('EmergencyTypeScreen description is optional when Other is selected',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestableWidget(const EmergencyTypeScreen()),
    );
    await tester.pumpAndSettle();

    // Tap 'Other Urgent Threat' category card
    final otherCard = find.text(EmergencyType.other.label);
    await tester.ensureVisible(otherCard);
    await tester.tap(otherCard);
    await tester.pumpAndSettle();

    // Verify 'OPTIONAL' badge appears
    expect(find.text('OPTIONAL'), findsOneWidget);

    // Transmit by holding SOS with empty description - should succeed because description is optional
    final sosButton = find.byType(SosButton);
    await tester.ensureVisible(sosButton);
    final gesture = await tester.startGesture(tester.getCenter(sosButton));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    // Verify transmission succeeded to SOS Sending Screen
    expect(find.text('SOS Sending Screen'), findsOneWidget);
  });

  testWidgets('EmergencyTypeScreen transmits custom description when provided with Other category',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestableWidget(const EmergencyTypeScreen()),
    );
    await tester.pumpAndSettle();

    // Select Other
    final otherCard = find.text(EmergencyType.other.label);
    await tester.ensureVisible(otherCard);
    await tester.tap(otherCard);
    await tester.pumpAndSettle();

    // Type description in multiline field
    final textField = find.byType(TextField);
    await tester.ensureVisible(textField);
    await tester.enterText(textField, 'Trapped in rising water, 2 victims injured');
    await tester.pumpAndSettle();

    // Transmit by holding SOS
    final sosButton = find.byType(SosButton);
    await tester.ensureVisible(sosButton);
    final gesture = await tester.startGesture(tester.getCenter(sosButton));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    // Verify transmission succeeded to SOS Sending Screen
    expect(find.text('SOS Sending Screen'), findsOneWidget);
  });

  testWidgets('HomeScreen directly renders HOLD SOS button, categories, and description',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.sosSending,
          builder: (context, state) =>
              const Scaffold(body: Text('SOS Sending Screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      buildTestableWidget(const SizedBox(), router: router),
    );
    await tester.pumpAndSettle();

    // Verify HomeScreen directly renders HOLD SOS button, categories and description
    expect(find.text('HOLD SOS TO TRANSMIT'), findsOneWidget);
    expect(find.byType(SosButton), findsOneWidget);
    expect(find.text('Select Emergency Category'), findsOneWidget);
    expect(find.text('Situation & Victim Description'), findsOneWidget);
  });

  testWidgets(
      'EmergencyTypeScreen renders identical emergency section when routed directly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final router = GoRouter(
      initialLocation: AppRoutes.emergencyTypes,
      routes: [
        GoRoute(
          path: AppRoutes.emergencyTypes,
          builder: (context, state) {
            return const EmergencyTypeScreen(initialType: EmergencyType.fire);
          },
        ),
      ],
    );

    await tester.pumpWidget(
      buildTestableWidget(const SizedBox(), router: router),
    );
    await tester.pumpAndSettle();

    // Verify EmergencyTypeScreen is reached with Fire selected
    expect(find.text('SOS Emergency Details'), findsOneWidget);
    expect(find.text('Selected: Fire'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets(
      'GuestSosScreen requires situation description when Other is selected',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildTestableWidget(const GuestSosScreen()),
    );
    await tester.pumpAndSettle();

    // Select Other category
    final otherCard = find.text(EmergencyType.other.label);
    await tester.ensureVisible(otherCard);
    await tester.tap(otherCard);
    await tester.pumpAndSettle();

    // Attempt to transmit without notes via SosButton 1500ms hold
    final sosButtonFinder = find.byType(SosButton);
    expect(sosButtonFinder, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(sosButtonFinder));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    // Verify warning snackbar is shown
    expect(
      find.text('Please describe the emergency situation when "Other" is selected.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'GuestSosScreen AppBar has canonical SORYNTH branding and distinct blue Sign In action',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestableWidget(const GuestSosScreen()),
    );
    await tester.pumpAndSettle();

    // 1. Verify AppBar exists and has correct background
    final appBarFinder = find.byType(AppBar);
    expect(appBarFinder, findsOneWidget);
    final appBar = tester.widget<AppBar>(appBarFinder);
    expect(appBar.backgroundColor, equals(AppColors.background));
    expect(appBar.elevation, equals(0));

    // 2. Verify Canonical SORYNTH brand header in AppBar
    expect(
      find.descendant(of: appBarFinder, matching: find.byType(SorynthLogo)),
      findsOneWidget,
    );
    final titleTextFinder = find.descendant(
      of: appBarFinder,
      matching: find.text('SORYNTH'),
    );
    expect(titleTextFinder, findsOneWidget);
    final titleText = tester.widget<Text>(titleTextFinder);
    expect(titleText.style?.color, equals(AppColors.textDark));
    expect(titleText.style?.fontWeight, equals(FontWeight.w900));

    expect(
      find.descendant(
        of: appBarFinder,
        matching: find.text('SIGNAL BEYOND BOUNDARIES'),
      ),
      findsOneWidget,
    );

    // 3. Verify Sign In Action has Primary Blue text and distinct styling
    final signInFinder = find.descendant(
      of: appBarFinder,
      matching: find.text('Sign In'),
    );
    expect(signInFinder, findsOneWidget);
    final signInText = tester.widget<Text>(signInFinder);
    expect(signInText.style?.color, equals(AppColors.primaryBlue));
    expect(signInText.style?.fontWeight, equals(FontWeight.w700));

    // 4. Verify Sign In Icon is present and colored
    final signInIconFinder = find.descendant(
      of: appBarFinder,
      matching: find.byIcon(Icons.login_rounded),
    );
    expect(signInIconFinder, findsOneWidget);
    final signInIcon = tester.widget<Icon>(signInIconFinder);
    expect(signInIcon.color, equals(AppColors.primaryBlue));
  });
}



