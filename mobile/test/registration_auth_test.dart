import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_colors.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/core/routing/app_router.dart';
import 'package:sorynth/core/theme/app_theme.dart';
import 'package:sorynth/data/models/user_profile.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/authentication/email_verification_screen.dart';
import 'package:sorynth/features/authentication/registration_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeSupabaseService extends SupabaseService {
  final Future<AuthResponse?> Function({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) onSignUp;

  FakeSupabaseService({required this.onSignUp});

  @override
  bool get isConfigured => true;

  @override
  Future<AuthResponse?> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? emailRedirectTo,
  }) async {
    return onSignUp(
      email: email,
      password: password,
      fullName: fullName,
      phone: phone,
    );
  }
}

class FakeUserProfileNotifier extends StateNotifier<UserProfile?>
    implements UserProfileNotifier {
  bool loadProfileCalled = false;

  FakeUserProfileNotifier() : super(null);

  @override
  Future<void> loadProfile() async {
    loadProfileCalled = true;
  }

  @override
  Future<void> updateProfile(UserProfile updated) async {
    state = updated;
  }

  @override
  void clear() {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget createTestWidget({
    required FakeSupabaseService fakeSupabase,
    FakeUserProfileNotifier? fakeProfileNotifier,
    GoRouter? customRouter,
    ThemeData? theme,
  }) {
    final profileNotifier = fakeProfileNotifier ?? FakeUserProfileNotifier();
    final router = customRouter ??
        GoRouter(
          initialLocation: AppRoutes.register,
          routes: [
            GoRoute(
              path: AppRoutes.register,
              builder: (context, state) => const RegistrationScreen(),
            ),
            GoRoute(
              path: AppRoutes.login,
              builder: (context, state) =>
                  const Scaffold(body: Text('Login Screen')),
            ),
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) =>
                  const Scaffold(body: Text('Home Screen')),
            ),
            GoRoute(
              path: AppRoutes.emailVerification,
              builder: (context, state) {
                final email = (state.extra as String?) ?? '';
                return EmailVerificationScreen(email: email);
              },
            ),
          ],
        );

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseServiceProvider.overrideWithValue(fakeSupabase),
        userProfileProvider.overrideWith((ref) => profileNotifier),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? AppTheme.lightTheme,
      ),
    );
  }

  Future<void> fillAndSubmitForm(WidgetTester tester) async {
    // Fill Full Name
    final nameField = find.widgetWithText(TextFormField, 'Full Name');
    await tester.enterText(nameField, 'Jane Doe');

    // Fill Phone
    final phoneField = find.widgetWithText(TextFormField, 'Enter Phone Number');
    await tester.enterText(phoneField, '+1234567890');

    // Fill Email
    final emailField = find.widgetWithText(TextFormField, 'Enter Email Address');
    await tester.enterText(emailField, 'janedoe@example.com');

    // Fill Password
    final passwordField = find.widgetWithText(TextFormField, 'Minimum 6 characters');
    await tester.enterText(passwordField, 'secret123');

    // Fill Confirm Password
    final confirmField = find.widgetWithText(TextFormField, 'Repeat password');
    await tester.enterText(confirmField, 'secret123');

    // Tap submit button
    final submitButton = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'RegistrationScreen maps over_email_send_rate_limit to friendly error message',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeSupabase = FakeSupabaseService(
      onSignUp: ({
        required String email,
        required String password,
        required String fullName,
        String? phone,
      }) async {
        throw const AuthException(
          'Email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        );
      },
    );

    await tester.pumpWidget(createTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await fillAndSubmitForm(tester);

    // Verify friendly error message is displayed
    expect(
      find.text('Too many verification email requests. Please wait before trying again.'),
      findsOneWidget,
    );
    // Ensure raw technical error is NOT shown
    expect(find.text('over_email_send_rate_limit'), findsNothing);
    expect(find.text('HTTP 429'), findsNothing);
  });

  testWidgets(
      'RegistrationScreen handles pending email verification without loadProfile or navigating to Home',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeProfileNotifier = FakeUserProfileNotifier();
    final fakeSupabase = FakeSupabaseService(
      onSignUp: ({
        required String email,
        required String password,
        required String fullName,
        String? phone,
      }) async {
        // Successful signup but session is null (email confirmation pending)
        return AuthResponse(
          user: User(
            id: 'unconfirmed-user-123',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-11-20T12:00:00Z',
          ),
          session: null,
        );
      },
    );

    await tester.pumpWidget(
      createTestWidget(
        fakeSupabase: fakeSupabase,
        fakeProfileNotifier: fakeProfileNotifier,
      ),
    );
    await tester.pumpAndSettle();

    await fillAndSubmitForm(tester);

    // Verify loadProfile was NOT called
    expect(fakeProfileNotifier.loadProfileCalled, isFalse);

    // Verify user is guided to Email Verification Screen, NOT Home Screen
    expect(find.text('Verify Your Email'), findsOneWidget);
    expect(find.text('janedoe@example.com'), findsOneWidget);
    expect(find.text('Home Screen'), findsNothing);
  });

  testWidgets(
      'RegistrationScreen handles immediate session by loading profile and navigating to Home',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeProfileNotifier = FakeUserProfileNotifier();
    final fakeSupabase = FakeSupabaseService(
      onSignUp: ({
        required String email,
        required String password,
        required String fullName,
        String? phone,
      }) async {
        // Active session granted immediately
        return AuthResponse(
          user: User(
            id: 'confirmed-user-456',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-11-20T12:00:00Z',
          ),
          session: Session(
            accessToken: 'token-123',
            tokenType: 'bearer',
            user: User(
              id: 'confirmed-user-456',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: '2026-11-20T12:00:00Z',
            ),
          ),
        );
      },
    );

    await tester.pumpWidget(
      createTestWidget(
        fakeSupabase: fakeSupabase,
        fakeProfileNotifier: fakeProfileNotifier,
      ),
    );
    await tester.pumpAndSettle();

    await fillAndSubmitForm(tester);

    // Verify loadProfile WAS called
    expect(fakeProfileNotifier.loadProfileCalled, isTrue);

    // Verify navigated to Home Screen
    expect(find.text('Home Screen'), findsOneWidget);
  });

  testWidgets('RegistrationScreen field labels and headings have accessible dark navy contrast',
      (WidgetTester tester) async {
    final fakeSupabase = FakeSupabaseService(
      onSignUp: ({required email, required password, required fullName, phone}) async => null,
    );

    await tester.pumpWidget(createTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    // 1. Verify AppBar title is dark navy
    final titleFinder = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Create Account'),
    );
    expect(titleFinder, findsOneWidget);
    final titleText = tester.widget<Text>(titleFinder);
    expect(titleText.style?.color, equals(AppColors.textDark));

    // 2. Verify Back button icon is dark navy
    final backIconFinder = find.byIcon(Icons.arrow_back_ios_new_rounded);
    expect(backIconFinder, findsOneWidget);
    final backIcon = tester.widget<Icon>(backIconFinder);
    expect(backIcon.color, equals(AppColors.textDark));

    // 3. Verify page heading is dark navy
    final headingFinder = find.text('Join SORYNTH');
    expect(headingFinder, findsOneWidget);
    final headingText = tester.widget<Text>(headingFinder);
    expect(headingText.style?.color, equals(AppColors.textDark));

    // 4. Verify all 5 field labels use dark navy text
    const expectedLabels = [
      'Full Name *',
      'Phone Number',
      'Email Address *',
      'Password *',
      'Confirm Password *',
    ];

    for (final label in expectedLabels) {
      final labelFinder = find.text(label);
      expect(labelFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(labelFinder);
      expect(
        textWidget.style?.color,
        equals(AppColors.textDark),
        reason: 'Label "$label" must have high-contrast dark navy color',
      );
      expect(
        textWidget.style?.fontWeight,
        equals(FontWeight.w700),
      );
    }
  });

  testWidgets('RegistrationScreen maintains accessible dark navy labels and white field fill under Dark Theme',
      (WidgetTester tester) async {
    final fakeSupabase = FakeSupabaseService(
      onSignUp: ({required email, required password, required fullName, phone}) async => null,
    );

    await tester.pumpWidget(
      createTestWidget(
        fakeSupabase: fakeSupabase,
        theme: AppTheme.darkTheme,
      ),
    );
    await tester.pumpAndSettle();

    // Verify background remains light background
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, equals(AppColors.background));

    // Verify AppBar title remains dark navy and does not wash out to white
    final titleFinder = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Create Account'),
    );
    expect(titleFinder, findsOneWidget);
    final titleText = tester.widget<Text>(titleFinder);
    expect(titleText.style?.color, equals(AppColors.textDark));

    // Verify back icon remains dark navy
    final backIcon = tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(backIcon.color, equals(AppColors.textDark));

    // Verify all 5 field labels remain dark navy even under dark theme
    const expectedLabels = [
      'Full Name *',
      'Phone Number',
      'Email Address *',
      'Password *',
      'Confirm Password *',
    ];

    for (final label in expectedLabels) {
      final labelFinder = find.text(label);
      expect(labelFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(labelFinder);
      expect(
        textWidget.style?.color,
        equals(AppColors.textDark),
        reason: 'Label "$label" must remain dark navy under dark theme',
      );
    }

    // Verify input fields maintain white fill and dark navy input text style
    final textField = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Full Name'),
        matching: find.byType(TextField),
      ),
    );
    expect(textField.style?.color, equals(AppColors.textDark));
    expect(textField.decoration?.fillColor, equals(AppColors.white));
  });
}
