import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/services/device_readiness_service.dart';
import '../../shared/widgets/sorynth_logo.dart';

class DeviceReadinessScreen extends ConsumerStatefulWidget {
  const DeviceReadinessScreen({super.key});

  @override
  ConsumerState<DeviceReadinessScreen> createState() =>
      _DeviceReadinessScreenState();
}

class _DeviceReadinessScreenState extends ConsumerState<DeviceReadinessScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User may have returned from Android system settings after enabling GPS/BT
      ref.read(deviceReadinessNotifierProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _proceedToApp() {
    final supabase = ref.read(supabaseServiceProvider);
    if (supabase.currentUser != null) {
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.guestSos);
    }
  }

  Future<void> _handleServiceAction(
    ServiceReadiness readiness,
    String serviceKey,
  ) async {
    final service = ref.read(deviceReadinessServiceProvider);
    final notifier = ref.read(deviceReadinessNotifierProvider.notifier);

    switch (serviceKey) {
      case 'bluetooth':
        if (readiness.isPermissionRequired) {
          if (readiness.actionLabel.contains('Settings')) {
            await service.openSettings();
          } else {
            await service.requestBluetoothPermission();
          }
        } else if (readiness.isDisabled) {
          await service.enableBluetooth();
        }
        break;

      case 'location':
        if (readiness.isPermissionRequired) {
          if (readiness.actionLabel.contains('Settings')) {
            await service.openSettings();
          } else {
            await service.requestLocationPermission();
          }
        } else if (readiness.isDisabled) {
          await service.openLocationSettings();
        }
        break;

      case 'internet':
        await service.openSettings();
        break;
    }

    await notifier.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(deviceReadinessNotifierProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor =
        isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Device Readiness'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.guestSos),
            icon: const Icon(Icons.emergency_rounded,
                size: 16, color: AppColors.emergencyRed),
            label: const Text(
              'Guest SOS',
              style: TextStyle(
                color: AppColors.emergencyRed,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: isDark
                      ? const []
                      : const [
                          BoxShadow(
                            color: AppColors.cardShadow,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    const SorynthLogo(size: 46, showText: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pre-Flight Safety Check',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Checking Bluetooth, GPS & Internet for emergency preparedness.',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryTextColor,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // CARD 1: Bluetooth BLE
              _buildServiceCard(
                serviceKey: 'bluetooth',
                readiness: readiness.bluetooth,
                isChecking: readiness.isChecking,
                cardBg: cardBg,
                borderColor: borderColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
              ),

              const SizedBox(height: 12),

              // CARD 2: Location & GPS
              _buildServiceCard(
                serviceKey: 'location',
                readiness: readiness.location,
                isChecking: readiness.isChecking,
                cardBg: cardBg,
                borderColor: borderColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
              ),

              const SizedBox(height: 12),

              // CARD 3: Internet & Cloud Uplink
              _buildServiceCard(
                serviceKey: 'internet',
                readiness: readiness.internet,
                isChecking: readiness.isChecking,
                cardBg: cardBg,
                borderColor: borderColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
              ),

              const SizedBox(height: 24),

              // Primary Continue Button
              ElevatedButton.icon(
                onPressed: _proceedToApp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: readiness.internet.isReady
                      ? AppColors.primaryBlue
                      : (isDark ? AppColors.darkCardSurface : AppColors.darkNavy),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  readiness.internet.isReady
                      ? Icons.arrow_forward_rounded
                      : Icons.cloud_off_rounded,
                  size: 20,
                ),
                label: Text(
                  readiness.internet.isReady
                      ? 'Continue to SORYNTH'
                      : 'Continue in Offline Mode',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Recheck button
              Center(
                child: TextButton.icon(
                  onPressed: () => ref
                      .read(deviceReadinessNotifierProvider.notifier)
                      .refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Re-scan Hardware & Services'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceCard({
    required String serviceKey,
    required ServiceReadiness readiness,
    required bool isChecking,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    final Color statusColor;
    final String statusLabel;

    switch (readiness.status) {
      case ServiceReadinessStatus.ready:
        statusColor = AppColors.successGreen;
        statusLabel = 'Ready';
        break;
      case ServiceReadinessStatus.attentionRequired:
        statusColor = AppColors.warningYellow;
        statusLabel = 'Offline Mode';
        break;
      case ServiceReadinessStatus.disabled:
        statusColor = AppColors.warningYellow;
        statusLabel = 'Disabled';
        break;
      case ServiceReadinessStatus.permissionRequired:
        statusColor = AppColors.emergencyRed;
        statusLabel = 'Permission Needed';
        break;
      case ServiceReadinessStatus.notAvailable:
        statusColor = AppColors.secondaryText;
        statusLabel = 'Not Available';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: readiness.isReady
              ? borderColor
              : statusColor.withValues(alpha: 0.35),
          width: readiness.isReady ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  readiness.icon,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readiness.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            readiness.description,
            style: TextStyle(
              fontSize: 12,
              color: secondaryTextColor,
              height: 1.35,
            ),
          ),
          if (!readiness.isReady &&
              readiness.status != ServiceReadinessStatus.notAvailable) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => _handleServiceAction(readiness, serviceKey),
                style: ElevatedButton.styleFrom(
                  backgroundColor: statusColor,
                  foregroundColor: AppColors.white,
                  minimumSize: const Size(120, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  readiness.actionLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
