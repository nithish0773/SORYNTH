import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';

class StatusBadge extends StatelessWidget {
  final EmergencyStatus status;
  final bool isCompact;

  const StatusBadge({
    super.key,
    required this.status,
    this.isCompact = false,
  });

  Color _getStatusColor() {
    switch (status) {
      case EmergencyStatus.gpsAcquiring:
      case EmergencyStatus.queuedLocally:
        return AppColors.warningYellow;
      case EmergencyStatus.gpsLocked:
      case EmergencyStatus.connectingToEsp32:
      case EmergencyStatus.transmittingViaLora:
      case EmergencyStatus.relayReceived:
      case EmergencyStatus.gatewayReceived:
        return AppColors.secondaryBlue;
      case EmergencyStatus.uploadedToServer:
      case EmergencyStatus.rescueTeamAcknowledged:
      case EmergencyStatus.resolved:
        return AppColors.successGreen;
      case EmergencyStatus.inAction:
        return AppColors.primaryBlue;
      case EmergencyStatus.cancelled:
      case EmergencyStatus.failed:
        return AppColors.emergencyRed;
    }
  }

  IconData _getStatusIcon() {
    switch (status) {
      case EmergencyStatus.gpsAcquiring:
        return Icons.location_searching_rounded;
      case EmergencyStatus.gpsLocked:
        return Icons.my_location_rounded;
      case EmergencyStatus.queuedLocally:
        return Icons.inventory_2_rounded;
      case EmergencyStatus.connectingToEsp32:
        return Icons.bluetooth_searching_rounded;
      case EmergencyStatus.transmittingViaLora:
        return Icons.cell_tower_rounded;
      case EmergencyStatus.relayReceived:
        return Icons.hub_rounded;
      case EmergencyStatus.gatewayReceived:
        return Icons.router_rounded;
      case EmergencyStatus.uploadedToServer:
        return Icons.cloud_done_rounded;
      case EmergencyStatus.rescueTeamAcknowledged:
        return Icons.verified_rounded;
      case EmergencyStatus.inAction:
        return Icons.local_shipping_rounded;
      case EmergencyStatus.resolved:
        return Icons.task_alt_rounded;
      case EmergencyStatus.cancelled:
        return Icons.cancel_rounded;
      case EmergencyStatus.failed:
        return Icons.error_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final icon = _getStatusIcon();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 12,
        vertical: isCompact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isCompact ? 13 : 16, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: isCompact ? 11 : 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
