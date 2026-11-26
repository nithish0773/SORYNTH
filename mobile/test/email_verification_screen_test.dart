import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_colors.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/core/routing/app_router.dart';
import 'package:sorynth/core/theme/app_theme.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/authentication/email_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockVerificationSupabaseService extends SupabaseService {
  final Future<void> Function(String email)? onResend;
  int resendCallCount = 0;

  MockVerificationSupabaseService({this.onResend});

  @override
  bool get isConfigured => true;

  @override
  Future<void> resendConfirmationEmail(
    String email, {
    String? emailRedirectTo,
  }) async {
    resendCallCount++;
    if (onResend != null) {
      return onResend!(email);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  void configureViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget createVerificationTestWidget({
    required MockVerificationSupabaseService fakeSupabase,
    String email = 'cadet@sorynth.org',
    ThemeData? theme,
  }) {
    final router = GoRouter(
      initialLocation: AppRoutes.emailVerification,
      routes: [
        GoRoute(
          path: AppRoutes.emailVerification,
          builder: (context, state) => EmailVerificationScreen(email: email),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) =>
              const Scaffold(body: Text('Login Screen Mock')),
        ),
        GoRoute(
          path: AppRoutes.register,
          builder: (context, state) =>
              const Scaffold(body: Text('Registration Screen Mock')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseServiceProvider.overrideWithValue(fakeSupabase),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? AppTheme.lightTheme,
      ),
    );
  }

  testWidgets(
      'EmailVerificationScreen renders heading, email, step cards, and action buttons',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService();

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'responder@sorynth.org',
      ),
    );
    await tester.pumpAndSettle();

    // Verify Heading
    expect(find.text('Verify Your Email'), findsOneWidget);

    // Verify registered email is displayed
    expect(find.text('responder@sorynth.org'), findsOneWidget);

    // Verify verification icon is present
    expect(find.byIcon(Icons.mark_email_unread_rounded), findsOneWidget);

    // Verify next steps card
    expect(find.text('Next Steps:'), findsOneWidget);
    expect(find.text('Open your email application or inbox.'), findsOneWidget);

    // Verify Resend Verification Email button is present and enabled
    final resendButtonFinder =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    expect(resendButtonFinder, findsOneWidget);

    // Verify Back to Sign In button is present
    final backButtonFinder =
        find.widgetWithText(ElevatedButton, 'Back to Sign In');
    expect(backButtonFinder, findsOneWidget);
  });

  testWidgets(
      'Tapping Resend Verification Email calls Supabase and initiates 60s cooldown timer',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService(
      onResend: (email) async {
        // Resend succeeded
      },
    );

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'cadet@sorynth.org',
      ),
    );
    await tester.pumpAndSettle();

    final resendButton =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    await tester.ensureVisible(resendButton);
    await tester.tap(resendButton);
    await tester.pumpAndSettle();

    // Verify call happened once
    expect(fakeSupabase.resendCallCount, equals(1));

    // Verify success banner is shown
    expect(
      find.text(
          'Verification email sent! Please check your inbox and spam folder.'),
      findsOneWidget,
    );

    // Verify button shows countdown and is disabled
    expect(find.text('Resend in 60s'), findsOneWidget);
    final buttonWidget = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Resend in 60s'),
    );
    expect(buttonWidget.onPressed, isNull);

    // Advance 1 second
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend in 59s'), findsOneWidget);
  });

  testWidgets(
      'Rapid repeated taps on Resend button are prevented while request is processing and during cooldown',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService(
      onResend: (email) async {
        await Future.delayed(const Duration(milliseconds: 100));
      },
    );

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'cadet@sorynth.org',
      ),
    );
    await tester.pumpAndSettle();

    final resendButton =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    await tester.ensureVisible(resendButton);

    // Tap rapidly multiple times
    await tester.tap(resendButton);
    await tester.tap(resendButton, warnIfMissed: false);
    await tester.tap(resendButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify call happened exactly once
    expect(fakeSupabase.resendCallCount, equals(1));
  });

  testWidgets(
      'Resend handles rate limits (HTTP 429 over_email_send_rate_limit) gracefully with friendly message',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService(
      onResend: (email) async {
        throw const AuthException(
          'Email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        );
      },
    );

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'cadet@sorynth.org',
      ),
    );
    await tester.pumpAndSettle();

    final resendButton =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    await tester.ensureVisible(resendButton);
    await tester.tap(resendButton);
    await tester.pumpAndSettle();

    // Verify friendly error message
    expect(
      find.text(
          'Too many requests. Please wait a moment before requesting another verification email.'),
      findsOneWidget,
    );

    // Verify button goes into cooldown to protect backend
    expect(find.text('Resend in 60s'), findsOneWidget);
  });

  testWidgets(
      'Resend handles network failure and displays actionable error message without claiming email was sent',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService(
      onResend: (email) async {
        throw Exception('SocketException: Failed host lookup');
      },
    );

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'cadet@sorynth.org',
      ),
    );
    await tester.pumpAndSettle();

    final resendButton =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    await tester.ensureVisible(resendButton);
    await tester.tap(resendButton);
    await tester.pumpAndSettle();

    // Verify network error message
    expect(
      find.text(
          'Network error. Please check your internet connection and try again.'),
      findsOneWidget,
    );

    // Verify it did NOT claim verification email was sent
    expect(find.text('Verification email sent! Please check your inbox and spam folder.'), findsNothing);
  });

  testWidgets('Back to Sign In button navigates to AppRoutes.login',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService();

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'cadet@sorynth.org',
      ),
    );
    await tester.pumpAndSettle();

    final backButton = find.widgetWithText(ElevatedButton, 'Back to Sign In');
    await tester.ensureVisible(backButton);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    expect(find.text('Login Screen Mock'), findsOneWidget);
  });

  testWidgets(
      'EmailVerificationScreen maintains high contrast and dark surfaces under Dark Theme',
      (WidgetTester tester) async {
    configureViewport(tester);
    final fakeSupabase = MockVerificationSupabaseService();

    await tester.pumpWidget(
      createVerificationTestWidget(
        fakeSupabase: fakeSupabase,
        email: 'cadet@sorynth.org',
        theme: AppTheme.darkTheme,
      ),
    );
    await tester.pumpAndSettle();

    // Verify dark scaffold background
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, equals(AppColors.darkBackground));

    // Verify title is white
    final title = tester.widget<Text>(find.text('Verify Your Email'));
    expect(title.style?.color, equals(AppColors.darkPrimaryText));

    // Verify back icon color is white
    final backIcon = tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(backIcon.color, equals(AppColors.darkPrimaryText));
  });
}
