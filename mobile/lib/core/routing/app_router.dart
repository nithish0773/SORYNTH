import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/emergency_model.dart';
import '../../features/authentication/email_verification_screen.dart';
import '../../features/authentication/login_screen.dart';
import '../../features/authentication/registration_screen.dart';
import '../../features/emergency/emergency_type_screen.dart';
import '../../features/emergency/sos_sending_screen.dart';
import '../../features/guest_sos/guest_sos_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/readiness/device_readiness_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/tracking/sos_active_screen.dart';
import '../../features/welcome/welcome_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String welcome = '/welcome';
  static const String guestSos = '/guest-sos';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String emergencyTypes = '/emergency-types';
  static const String sosSending = '/sos-sending';
  static const String sosActive = '/sos-active';
  static const String history = '/history';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String deviceReadiness = '/device-readiness';
  static const String emailVerification = '/email-verification';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.splash,
      builder: (BuildContext context, GoRouterState state) {
        return const SplashScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.deviceReadiness,
      builder: (BuildContext context, GoRouterState state) {
        return const DeviceReadinessScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (BuildContext context, GoRouterState state) {
        return const OnboardingScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.welcome,
      builder: (BuildContext context, GoRouterState state) {
        return const WelcomeScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.guestSos,
      builder: (BuildContext context, GoRouterState state) {
        return const GuestSosScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (BuildContext context, GoRouterState state) {
        return const LoginScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.register,
      builder: (BuildContext context, GoRouterState state) {
        return const RegistrationScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.emergencyTypes,
      builder: (BuildContext context, GoRouterState state) {
        final initialType = state.extra as EmergencyType?;
        return EmergencyTypeScreen(initialType: initialType);
      },
    ),
    GoRoute(
      path: AppRoutes.sosSending,
      builder: (BuildContext context, GoRouterState state) {
        final emergency = state.extra as EmergencyModel?;
        return SosSendingScreen(emergency: emergency);
      },
    ),
    GoRoute(
      path: AppRoutes.sosActive,
      builder: (BuildContext context, GoRouterState state) {
        final emergency = state.extra as EmergencyModel?;
        return SosActiveScreen(initialEmergency: emergency);
      },
    ),
    GoRoute(
      path: AppRoutes.history,
      builder: (BuildContext context, GoRouterState state) {
        return const HistoryScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.profile,
      builder: (BuildContext context, GoRouterState state) {
        return const ProfileScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (BuildContext context, GoRouterState state) {
        return const SettingsScreen();
      },
    ),
    GoRoute(
      path: AppRoutes.emailVerification,
      builder: (BuildContext context, GoRouterState state) {
        final email = (state.extra as String?) ?? '';
        return EmailVerificationScreen(email: email);
      },
    ),
  ],
);
