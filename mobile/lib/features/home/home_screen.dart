import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/emergency_model.dart';
import '../../shared/widgets/connectivity_banner.dart';
import '../../shared/widgets/sorynth_logo.dart';
import '../../shared/widgets/status_badge.dart';
import '../emergency/widgets/logged_in_sos_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(userProfileProvider);
    final history = ref.watch(emergencyHistoryProvider);
    final activeEmergency = ref.watch(activeEmergencyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        elevation: 0.5,
        scrolledUnderElevation: 2,
        title: Row(
          children: [
            const SorynthLogo(size: 38, showText: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SORYNTH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: isDark ? AppColors.white : AppColors.textDark,
                    ),
                  ),
                  Text(
                    'SIGNAL BEYOND BOUNDARIES',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isDark ? AppColors.secondaryBlue : AppColors.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Hardware BLE Mode Pill
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Chip(
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              avatar: const Icon(
                Icons.bluetooth_connected_rounded,
                size: 14,
                color: AppColors.successGreen,
              ),
              label: const Text(
                'BLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.successGreen,
                ),
              ),
              backgroundColor: AppColors.successGreen.withValues(alpha: 0.1),
              side: BorderSide(
                color: AppColors.successGreen.withValues(alpha: 0.3),
              ),
            ),
          ),

          IconButton(
            icon: Icon(
              Icons.person_outline_rounded,
              color: isDark ? AppColors.white : AppColors.textDark,
            ),
            tooltip: 'Profile & Settings',
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Greeting
              Text(
                'Hello, ${userProfile?.fullName ?? 'Civilian Responder'}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.white : AppColors.textDark,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Emergency standby system active. Hold SOS or select category to dispatch.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),

              const SizedBox(height: 10),

              // Active Emergency Banner (only genuinely active emergencies)
              if (activeEmergency != null && activeEmergency.isGenuinelyActive) ...[
                _buildActiveEmergencyBanner(context, activeEmergency),
                const SizedBox(height: 12),
              ],

              // Connectivity & Hardware Telemetry Banner
              const ConnectivityBanner(),

              const SizedBox(height: 12),

              // Direct Logged-In SOS Controls: 1. HOLD SOS button, 2. Category selection, 3. Optional description
              const LoggedInSosSection(),

              const SizedBox(height: 28),

              // Recent Emergency History Preview
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Recent Transmissions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.history),
                    child: const Text('Full History'),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              if (history.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCardSurface : AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.borderLight),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppColors.successGreen,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No active or past emergencies',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkSecondaryText : AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...history.take(2).map((em) => _buildHistoryMiniCard(context, em)),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveEmergencyBanner(BuildContext context, EmergencyModel emergency) {
    return InkWell(
      onTap: () => context.push(AppRoutes.sosActive, extra: emergency),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.emergencyRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.emergencyRed, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.emergencyRed,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'ACTIVE SOS: ${emergency.emergencyId}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.emergencyRed,
                        ),
                      ),
                      StatusBadge(
                        status: emergency.status,
                        isCompact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${emergency.emergencyType.label} • Tap to view tracking & telemetry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: AppColors.emergencyRed),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryMiniCard(BuildContext context, EmergencyModel em) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCardSurface : AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      em.emergencyId,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.white : AppColors.textDark,
                      ),
                    ),
                    StatusBadge(status: em.status, isCompact: true),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${em.emergencyType.label} • ${em.communicationMethod.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkSecondaryText : AppColors.secondaryText,
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

