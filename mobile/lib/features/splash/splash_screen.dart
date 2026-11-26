import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/services/device_readiness_service.dart';
import '../../shared/widgets/sorynth_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;

    final storage = ref.read(offlineStorageServiceProvider);
    // Initialize/load local guest emergency identity
    storage.getOrCreateGuestId();

    final supabase = ref.read(supabaseServiceProvider);

    // If an authenticated session exists, preserve registered user experience
    if (supabase.currentUser != null) {
      context.go(AppRoutes.home);
      return;
    }

    final onboardingDone = storage.isOnboardingCompleted();
    if (!onboardingDone) {
      context.go(AppRoutes.onboarding);
      return;
    }

    // Evaluate hardware & permission device readiness if route is available
    final hasReadinessRoute = GoRouter.of(context).configuration.routes.any(
          (r) => r is GoRoute && r.path == AppRoutes.deviceReadiness,
        );

    if (hasReadinessRoute) {
      final readiness =
          await ref.read(deviceReadinessServiceProvider).checkAll();
      if (!mounted) return;

      if (readiness.hasIssues) {
        context.go(AppRoutes.deviceReadiness);
        return;
      }
    }

    // Default emergency-first route: directly to Guest SOS
    context.go(AppRoutes.guestSos);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background ambient radar pulses
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 320 * _pulseAnimation.value,
                height: 320 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.secondaryBlue.withValues(alpha: 0.12),
                    width: 2.0,
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 220 * _pulseAnimation.value,
                height: 220 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    width: 2.5,
                  ),
                ),
              );
            },
          ),

          // Central Logo and Branding
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: const SorynthLogo(
                    size: 96,
                    isDarkBackground: true,
                    showText: false,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'SORYNTH',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.secondaryBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'SIGNAL BEYOND BOUNDARIES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      color: AppColors.secondaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Loading Spinner & LoRa Status
          Positioned(
            bottom: 48,
            child: Column(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.secondaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Initializing Hybrid Radio Stack...',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.8),
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
