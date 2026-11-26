import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../data/services/bluetooth_service.dart';

class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[ConnectivityBanner] build() executed');
    final isOnlineAsync = ref.watch(isOnlineStreamProvider);
    final isOnline = isOnlineAsync.value ?? false;
    debugPrint(
        '[ConnectivityBanner] isOnlineAsync: ${isOnlineAsync.toString()}, resolved isOnline: $isOnline');

    final gpsState = ref.watch(gpsNotifierProvider);
    final hasGps = gpsState.value?.isSuccess ?? false;

    final bleState = ref.watch(bluetoothTelemetryStreamProvider);
    final bleTelemetry = bleState.value ?? ref.watch(bluetoothServiceProvider).currentTelemetry;
    final isBleConnected = bleTelemetry.status == BleConnectionStatus.connected;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Internet Indicator
          _buildPill(
            icon: isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            label: isOnline ? 'Online' : 'Offline',
            color: isOnline ? AppColors.successGreen : AppColors.secondaryText,
          ),

          const SizedBox(width: 8),

          // GPS Indicator
          _buildPill(
            icon: hasGps ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
            label: hasGps
                ? (gpsState.value != null && gpsState.value!.accuracy > 0
                    ? (gpsState.value!.isAccurate
                        ? 'GPS ±${gpsState.value!.accuracy.round()}m'
                        : 'Approx ±${gpsState.value!.accuracy.round()}m')
                    : 'GPS Locked')
                : 'Locating...',
            color: hasGps
                ? (gpsState.value?.isAccurate == true ? AppColors.primaryBlue : AppColors.secondaryBlue)
                : AppColors.warningYellow,
          ),

          const SizedBox(width: 8),

          // LoRa / BLE Transceiver Indicator
          _buildPill(
            icon: Icons.cell_tower_rounded,
            label: isBleConnected ? 'LoRa Ready' : 'LoRa Standby',
            color: isBleConnected ? AppColors.successGreen : AppColors.secondaryText,
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

