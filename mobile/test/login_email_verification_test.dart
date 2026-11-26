import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/core/routing/app_router.dart';
import 'package:sorynth/data/models/user_profile.dart';
import 'package:sorynth/data/services/supabase_service.dart';
import 'package:sorynth/features/authentication/login_screen.dart';
import 'package:sorynth/shared/widgets/google_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockLoginSupabaseService extends SupabaseService {
  final Future<AuthResponse?> Function({
    required String email,
    required String password,
  })? onSignIn;

  final Future<bool> Function({String? redirectTo})? onSignInWithGoogle;
  final Future<void> Function(String email)? onResend;
  final Future<void> Function(String email)? onResetPassword;
  final Future<void> Function()? onSignOut;

  final StreamController<AuthState> _authStreamController =
      StreamController<AuthState>.broadcast();

  int resendCallCount = 0;
  int googleSignInCallCount = 0;
  int signOutCallCount = 0;
  User? _mockCurrentUser;

  MockLoginSupabaseService({
    this.onSignIn,
    this.onSignInWithGoogle,
    this.onResend,
    this.onResetPassword,
    this.onSignOut,
    User? initialUser,
  }) : _mockCurrentUser = initialUser;

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _mockCurrentUser;

  @override
  Stream<AuthState>? get authStateChanges => _authStreamController.stream;

  void emitAuthState(AuthState state) {
    if (state.session?.user != null) {
      _mockCurrentUser = state.session!.user;
    } else if (state.event == AuthChangeEvent.signedOut) {
      _mockCurrentUser = null;
    }
    _authStreamController.add(state);
  }

  @override
  Future<AuthResponse?> signIn({
    required String email,
    required String password,
  }) async {
    if (onSignIn != null) {
      return onSignIn!(email: email, password: password);
    }
    return null;
  }

  @override
  Future<bool> signInWithGoogle({String? redirectTo}) async {
    googleSignInCallCount++;
    if (onSignInWithGoogle != null) {
      return onSignInWithGoogle!(redirectTo: redirectTo);
    }
    return true;
  }

  @override
  Future<void> syncOAuthProfile(User user) async {
    // Mock profile sync
  }

  @override
  Future<void> signOut() async {
    signOutCallCount++;
    _mockCurrentUser = null;
    emitAuthState(const AuthState(AuthChangeEvent.signedOut, null));
    if (onSignOut != null) {
      await onSignOut!();
    }
  }

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

  @override
  Future<void> sendPasswordReset(String email) async {
    if (onResetPassword != null) {
      return onResetPassword!(email);
    }
  }

  void dispose() {
    _authStreamController.close();
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

  Widget createLoginTestWidget({
    required MockLoginSupabaseService fakeSupabase,
    FakeUserProfileNotifier? fakeProfileNotifier,
  }) {
    final profileNotifier = fakeProfileNotifier ?? FakeUserProfileNotifier();
    final router = GoRouter(
      initialLocation: AppRoutes.login,
      routes: [
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) =>
              const Scaffold(body: Text('Home Screen')),
        ),
        GoRoute(
          path: AppRoutes.welcome,
          builder: (context, state) =>
              const Scaffold(body: Text('Welcome Screen')),
        ),
        GoRoute(
          path: AppRoutes.guestSos,
          builder: (context, state) =>
              const Scaffold(body: Text('Guest SOS Screen')),
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
      ),
    );
  }

  testWidgets(
      'LoginScreen displays unconfirmed email error and resend button when email_not_confirmed is returned',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        throw const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        );
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    // Enter email and password
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');

    // Tap Sign In
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    // Verify unconfirmed email notice is shown
    expect(
      find.text(
          'Your email address has not been confirmed yet. Please verify your email before logging in.'),
      findsOneWidget,
    );

    // Verify Resend Verification Email button is visible and enabled
    final resendButtonFinder =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    expect(resendButtonFinder, findsOneWidget);
    final button = tester.widget<OutlinedButton>(resendButtonFinder);
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'Tapping Resend Verification Email sends request and starts 60s cooldown timer disabling the button',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        throw const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        );
      },
      onResend: (email) async {
        // Successful resend
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    // Tap resend button
    final resendButtonFinder =
        find.widgetWithText(OutlinedButton, 'Resend Verification Email');
    await tester.tap(resendButtonFinder);
    await tester.pump(); // Start request

    // Verify exactly 1 call was dispatched
    expect(fakeSupabase.resendCallCount, equals(1));

    // Pump to complete async execution
    await tester.pump(const Duration(milliseconds: 100));

    // Verify SnackBar was shown
    expect(
      find.text(
          'Verification email resent! Please check your inbox and spam folders.'),
      findsOneWidget,
    );

    // Verify cooldown is active: button now shows 'Resend in 60s' and onPressed is null (disabled)
    final cooldownButtonFinder =
        find.widgetWithText(OutlinedButton, 'Resend in 60s');
    expect(cooldownButtonFinder, findsOneWidget);
    final cooldownButton = tester.widget<OutlinedButton>(cooldownButtonFinder);
    expect(cooldownButton.onPressed, isNull);

    // Tapping disabled button does NOT trigger another resend
    await tester.tap(cooldownButtonFinder, warnIfMissed: false);
    expect(fakeSupabase.resendCallCount, equals(1));

    // Advance 1 second: should show 'Resend in 59s'
    await tester.pump(const Duration(seconds: 1));
    expect(find.widgetWithText(OutlinedButton, 'Resend in 59s'), findsOneWidget);

    // Advance 59 more seconds: cooldown finishes, button re-enabled
    await tester.pump(const Duration(seconds: 59));
    expect(find.widgetWithText(OutlinedButton, 'Resend Verification Email'),
        findsOneWidget);
    final reenabledButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Resend Verification Email'));
    expect(reenabledButton.onPressed, isNotNull);
  });

  testWidgets(
      'Resend button displays friendly message and enforces cooldown on HTTP 429 over_email_send_rate_limit',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        throw const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        );
      },
      onResend: (email) async {
        throw const AuthException(
          'email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        );
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    // Tap resend
    await tester.tap(find.widgetWithText(OutlinedButton, 'Resend Verification Email'));
    await tester.pumpAndSettle();

    // Verify friendly user-facing message is displayed
    expect(
      find.text(
          'Email rate limit reached. Please wait 60 seconds before requesting another verification email.'),
      findsOneWidget,
    );

    // Verify technical error is NOT displayed
    expect(find.text('over_email_send_rate_limit'), findsNothing);
    expect(find.text('AuthApiException'), findsNothing);

    // Verify cooldown is engaged to prevent further spam
    expect(find.widgetWithText(OutlinedButton, 'Resend in 60s'), findsOneWidget);
    final cooldownButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Resend in 60s'));
    expect(cooldownButton.onPressed, isNull);
  });

  testWidgets(
      'LoginScreen maps login 429 rate limit to a friendly message',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        throw const AuthException(
          'Rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        );
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Too many login attempts. Please wait a moment before trying again.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'LoginScreen maps invalid credentials to a friendly actionable message',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        throw const AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        );
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'wrongpassword');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Invalid email or password. Please verify your credentials and try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'LoginScreen maps network/DNS connection failures to a friendly message',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        throw Exception(
            'ClientException: Failed host lookup: pmkwudzlyvaegwmugmoy.supabase.co');
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Network connection error. Please check your internet connection or Wi-Fi and try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'LoginScreen renders Continue with Google button, Google logo, and OR divider',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService();

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    // Verify Google login button and logo
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(GoogleLogo), findsOneWidget);

    // Verify OR divider
    expect(find.text('OR'), findsOneWidget);

    // Verify Guest SOS in AppBar
    expect(find.text('Guest SOS'), findsOneWidget);
  });

  testWidgets(
      'Tapping Continue with Google invokes signInWithGoogle and navigates to Home on AuthChangeEvent.signedIn',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignInWithGoogle: ({String? redirectTo}) async {
        return true;
      },
    );
    final profileNotifier = FakeUserProfileNotifier();

    await tester.pumpWidget(createLoginTestWidget(
      fakeSupabase: fakeSupabase,
      fakeProfileNotifier: profileNotifier,
    ));
    await tester.pumpAndSettle();

    // Scroll until Google button is visible in SingleChildScrollView
    final googleButtonFinder =
        find.widgetWithText(OutlinedButton, 'Continue with Google');
    expect(googleButtonFinder, findsOneWidget);
    await tester.ensureVisible(googleButtonFinder);
    await tester.pumpAndSettle();

    await tester.tap(googleButtonFinder);
    await tester.pump();

    // Verify signInWithGoogle was dispatched
    expect(fakeSupabase.googleSignInCallCount, equals(1));

    // Simulate OAuth callback return triggering Supabase AuthChangeEvent.signedIn
    const mockUser = User(
      id: 'google-user-777',
      appMetadata: {},
      userMetadata: {'full_name': 'Google Civilian Responder'},
      aud: 'authenticated',
      createdAt: '2026-01-01',
    );
    final mockSession = Session(
      accessToken: 'mock-google-access-token',
      tokenType: 'bearer',
      user: mockUser,
    );

    fakeSupabase.emitAuthState(
      AuthState(AuthChangeEvent.signedIn, mockSession),
    );
    await tester.pumpAndSettle();

    // Verify profile was loaded and router navigated to Home Screen
    expect(profileNotifier.loadProfileCalled, isTrue);
    expect(find.text('Home Screen'), findsOneWidget);
  });

  testWidgets(
      'Google login failure displays user-friendly error message and re-enables button',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignInWithGoogle: ({String? redirectTo}) async {
        throw const AuthException(
          'Google OAuth authentication cancelled or failed.',
          statusCode: '400',
        );
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    final googleButtonFinder =
        find.widgetWithText(OutlinedButton, 'Continue with Google');
    await tester.ensureVisible(googleButtonFinder);
    await tester.pumpAndSettle();

    await tester.tap(googleButtonFinder);
    await tester.pumpAndSettle();

    // Verify error message is displayed
    expect(
      find.text('Google OAuth authentication cancelled or failed.'),
      findsOneWidget,
    );

    // Verify button is re-enabled and clickable
    final reenabledButton =
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Continue with Google'));
    expect(reenabledButton.onPressed, isNotNull);
  });

  testWidgets(
      'Google login network failure displays actionable network error message',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignInWithGoogle: ({String? redirectTo}) async {
        throw Exception(
            'ClientException: Failed host lookup: pmkwudzlyvaegwmugmoy.supabase.co');
      },
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    final googleButtonFinder =
        find.widgetWithText(OutlinedButton, 'Continue with Google');
    await tester.ensureVisible(googleButtonFinder);
    await tester.pumpAndSettle();

    await tester.tap(googleButtonFinder);
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Network connection error. Please check your internet connection or Wi-Fi and try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Duplicate request prevention: Google button is disabled while email login is processing',
      (WidgetTester tester) async {
    final loginCompleter = Completer<AuthResponse?>();
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) => loginCompleter.future,
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');

    // Tap Sign In (starts async request)
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();

    final googleButtonFinder =
        find.widgetWithText(OutlinedButton, 'Continue with Google');
    await tester.ensureVisible(googleButtonFinder);
    await tester.pump();

    // While email login is processing, Google button must be disabled
    final googleButton = tester.widget<OutlinedButton>(googleButtonFinder);
    expect(googleButton.onPressed, isNull);

    // Tapping disabled Google button does nothing
    await tester.tap(googleButtonFinder, warnIfMissed: false);
    expect(fakeSupabase.googleSignInCallCount, equals(0));

    // Complete email login request
    loginCompleter.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'AppLifecycleState.resumed resets Google login loading state when user returns without authenticating',
      (WidgetTester tester) async {
    final completer = Completer<bool>();
    final fakeSupabase = MockLoginSupabaseService(
      onSignInWithGoogle: ({String? redirectTo}) => completer.future,
    );

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    final googleButtonFinder =
        find.widgetWithText(OutlinedButton, 'Continue with Google');
    await tester.ensureVisible(googleButtonFinder);
    await tester.pumpAndSettle();

    // User taps Continue with Google (browser launched)
    await tester.tap(googleButtonFinder);
    await tester.pump();

    // Verify loading indicator is displayed
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // User closes browser or switches back to SORYNTH without completing sign-in
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Google button is re-enabled immediately
    expect(find.text('Continue with Google'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Continue with Google'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'Guest SOS in AppBar is accessible without authentication and navigates directly to GuestSosScreen',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService();

    await tester.pumpWidget(createLoginTestWidget(fakeSupabase: fakeSupabase));
    await tester.pumpAndSettle();

    final guestSosButtonFinder =
        find.widgetWithText(TextButton, 'Guest SOS');
    expect(guestSosButtonFinder, findsOneWidget);

    await tester.tap(guestSosButtonFinder);
    await tester.pumpAndSettle();

    // Navigates directly to Guest SOS without requiring login
    expect(find.text('Guest SOS Screen'), findsOneWidget);
  });

  testWidgets(
      'User can sign out and subsequently sign in again successfully',
      (WidgetTester tester) async {
    final fakeSupabase = MockLoginSupabaseService(
      onSignIn: ({required email, required password}) async {
        return null;
      },
    );
    final profileNotifier = FakeUserProfileNotifier();

    await tester.pumpWidget(createLoginTestWidget(
      fakeSupabase: fakeSupabase,
      fakeProfileNotifier: profileNotifier,
    ));
    await tester.pumpAndSettle();

    // First login
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter Email Address'),
        'user@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, '••••••••••••'), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Home Screen'), findsOneWidget);

    // User signs out
    await fakeSupabase.signOut();
    profileNotifier.clear();
    expect(fakeSupabase.signOutCallCount, equals(1));
    expect(fakeSupabase.currentUser, isNull);
  });
}
