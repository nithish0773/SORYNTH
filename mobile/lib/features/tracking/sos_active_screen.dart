import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/emergency_model.dart';
import '../../shared/widgets/status_badge.dart';

class SosActiveScreen extends ConsumerStatefulWidget {
  final EmergencyModel? initialEmergency;

  const SosActiveScreen({super.key, this.initialEmergency});

  @override
  ConsumerState<SosActiveScreen> createState() => _SosActiveScreenState();
}

class _SosActiveScreenState extends ConsumerState<SosActiveScreen>
    with SingleTickerProviderStateMixin {
  EmergencyModel? _emergency;
  Timer? _refreshTimer;
  StreamSubscription<EmergencyModel>? _updatesSub;
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initEmergency();

    _updatesSub = ref
        .read(emergencyRepositoryProvider)
        .emergencyUpdatesStream
        .listen((updated) {
      final currentId = _emergency?.emergencyId ??
          widget.initialEmergency?.emergencyId ??
          ref.read(emergencyRepositoryProvider).getActiveEmergencyId();
      if (currentId == updated.emergencyId && mounted) {
        setState(() {
          _emergency = updated;
        });
      }
    });

    // Periodic check for rescue dispatch updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pollStatusUpdate();
    });
  }

  void _initEmergency() {
    final targetId = widget.initialEmergency?.emergencyId ??
        ref.read(activeEmergencyProvider)?.emergencyId ??
        ref.read(emergencyRepositoryProvider).getActiveEmergencyId();

    if (targetId != null) {
      final persisted =
          ref.read(emergencyRepositoryProvider).getEmergency(targetId);
      _emergency = persisted ??
          widget.initialEmergency ??
          ref.read(activeEmergencyProvider);
    } else {
      _emergency =
          widget.initialEmergency ?? ref.read(activeEmergencyProvider);
    }

    if (_emergency != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(activeEmergencyProvider)?.emergencyId !=
                _emergency?.emergencyId) {
          ref.read(activeEmergencyProvider.notifier).setActive(_emergency!);
        }
      });
    }
  }

  Future<void> _pollStatusUpdate() async {
    final currentId = _emergency?.emergencyId ??
        widget.initialEmergency?.emergencyId ??
        ref.read(activeEmergencyProvider)?.emergencyId ??
        ref.read(emergencyRepositoryProvider).getActiveEmergencyId();
    if (currentId == null) return;

    // 1. Check local storage first (handles background sync updates)
    final local =
        ref.read(emergencyRepositoryProvider).getEmergency(currentId);
    if (local != null && local.status != _emergency?.status) {
      if (mounted) {
        setState(() => _emergency = local);
        ref.read(activeEmergencyProvider.notifier).setActive(local);
        ref.read(emergencyHistoryProvider.notifier).refresh();
      }
    }

    // 2. Poll Supabase RPC if online
    try {
      final supabase = ref.read(supabaseServiceProvider);
      final updated = await supabase.getEmergencyStatus(currentId);
      if (updated != null && mounted) {
        setState(() => _emergency = updated);
        await ref.read(offlineStorageServiceProvider).saveEmergency(updated);
        ref.read(activeEmergencyProvider.notifier).setActive(updated);
        ref.read(emergencyHistoryProvider.notifier).refresh();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _updatesSub?.cancel();
    _radarController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCancel() async {
    final currentId = _emergency?.emergencyId ??
        widget.initialEmergency?.emergencyId ??
        ref.read(activeEmergencyProvider)?.emergencyId;

    if (currentId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Active SOS?'),
        content: const Text(
          'Are you safe? Cancelling will stand down dispatched search and rescue teams.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay Active'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergencyRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(emergencyRepositoryProvider)
          .cancelEmergency(currentId);
      ref.read(activeEmergencyProvider.notifier).cancelActive();
      ref.read(emergencyHistoryProvider.notifier).refresh();

      if (mounted) {
        _handleBackNavigation();
      }
    }
  }

  void _handleBackNavigation() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    final isGuest = _emergency?.isGuest ?? true;
    final currentUser = ref.read(supabaseServiceProvider).currentUser;

    if (isGuest || currentUser == null) {
      context.go(AppRoutes.guestSos);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final cardBorder = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryText = isDark ? AppColors.darkPrimaryText : AppColors.textDark;
    final secondaryText = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    final activeFromProvider = ref.watch(activeEmergencyProvider);
    final targetId = widget.initialEmergency?.emergencyId ??
        _emergency?.emergencyId ??
        ref.read(emergencyRepositoryProvider).getActiveEmergencyId();

    ref.listen<EmergencyModel?>(activeEmergencyProvider, (prev, next) {
      if (next != null && (targetId == null || next.emergencyId == targetId)) {
        _emergency = next;
      }
    });

    final persisted = targetId != null
        ? ref.read(emergencyRepositoryProvider).getEmergency(targetId)
        : null;
    final em = (activeFromProvider != null &&
            (targetId == null || activeFromProvider.emergencyId == targetId))
        ? activeFromProvider
        : (persisted ?? _emergency);

    if (em == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBackNavigation();
        },
        child: Scaffold(
          backgroundColor: scaffoldBg,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: _handleBackNavigation,
            ),
            title: const Text('Emergency Tracking'),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: 64, color: AppColors.successGreen),
                const SizedBox(height: 16),
                Text(
                  'No Active Emergency Broadcast',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryText),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _handleBackNavigation,
                  child: const Text('Return to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final dateStr = DateFormat('MMM dd, yyyy • hh:mm:ss a').format(em.timestamp);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: _handleBackNavigation,
          ),
          title: Text(
            'Active SOS: ${em.emergencyId}',
            style: const TextStyle(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Check Status Update',
              onPressed: _pollStatusUpdate,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Emergency ID & Status Hero Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withValues(alpha: 0.3) : AppColors.cardShadow,
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          em.emergencyId,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: AppColors.emergencyRed,
                          ),
                        ),
                        StatusBadge(status: em.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${em.emergencyType.label} • ${em.isGuest ? 'Guest Alert' : 'Registered User'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryText,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Live Radar / Tracking Map Visualization Widget
              _buildRadarTrackingWidget(em),

              const SizedBox(height: 16),

              // Telemetry & Network Details Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Distress Telemetry & Radio Route',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _buildInfoRow(
                      icon: Icons.navigation_rounded,
                      label: 'GPS Coordinates',
                      value: em.hasValidCoordinates
                          ? '${em.latitude.toStringAsFixed(6)}, ${em.longitude.toStringAsFixed(6)}'
                          : 'Location Unavailable',
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                    ),
                    Divider(height: 20, color: cardBorder),

                    _buildInfoRow(
                      icon: Icons.gps_fixed_rounded,
                      label: 'GPS Accuracy Range & Quality',
                      value: '${em.accuracyFormatted} • ${em.accuracyQualityLabel}',
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                    ),
                    Divider(height: 20, color: cardBorder),

                    _buildInfoRow(
                      icon: Icons.hub_rounded,
                      label: 'Communication Route',
                      value: em.communicationMethod.displayName,
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                    ),
                    Divider(height: 20, color: cardBorder),

                    _buildInfoRow(
                      icon: Icons.repeat_rounded,
                      label: 'LoRa Mesh Relay Hops',
                      value: '${em.hopCount} Hops (${em.relayPath.isNotEmpty ? em.relayPath.join(' -> ') : 'Direct'})',
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                    ),
                    Divider(height: 20, color: cardBorder),

                    _buildInfoRow(
                      icon: Icons.message_outlined,
                      label: 'Civilian Message',
                      value: em.message,
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                    ),
                    Divider(height: 20, color: cardBorder),

                    _buildInfoRow(
                      icon: em.isServerConfirmed
                          ? Icons.cloud_done_rounded
                          : (em.status == EmergencyStatus.gatewayReceived
                              ? Icons.router_rounded
                              : Icons.pending_actions_rounded),
                      label: 'Server Delivery Status',
                      value: em.deliveryStatusLabel,
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                    ),
                    if (em.wasQueuedOffline) ...[
                      Divider(height: 20, color: cardBorder),
                      _buildInfoRow(
                        icon: Icons.history_toggle_off_rounded,
                        label: 'Transmission Pipeline History',
                        value:
                            'Initially queued offline • Successfully delivered via cloud uplink upon network restoration',
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Cancel SOS Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.emergencyRed,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.emergencyRed, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text(
                    'I Am Safe • Stand Down SOS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildRadarTrackingWidget(EmergencyModel em) {
    return Container(
      width: double.infinity,
      height: 230,
      decoration: BoxDecoration(
        color: AppColors.darkNavy,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radar concentric rings
          ...[0.3, 0.6, 0.9].map(
            (ratio) => Container(
              width: 200 * ratio,
              height: 200 * ratio,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.secondaryBlue.withValues(alpha: 0.2),
                  width: 1.2,
                ),
              ),
            ),
          ),

          // Crosshairs
          Container(
            width: 180,
            height: 1,
            color: AppColors.secondaryBlue.withValues(alpha: 0.15),
          ),
          Container(
            width: 1,
            height: 180,
            color: AppColors.secondaryBlue.withValues(alpha: 0.15),
          ),

          // Radar sweep line
          RotationTransition(
            turns: _radarController,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  center: Alignment.center,
                  colors: [
                    AppColors.secondaryBlue.withValues(alpha: 0.0),
                    AppColors.secondaryBlue.withValues(alpha: 0.35),
                  ],
                  stops: const [0.75, 1.0],
                ),
              ),
            ),
          ),

          // Target GPS Blip
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.emergencyRed,
              boxShadow: [
                BoxShadow(
                  color: AppColors.emergencyRed.withValues(alpha: 0.6),
                  blurRadius: 14,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.person_pin_circle_rounded,
                  color: AppColors.white, size: 14),
            ),
          ),

          // Header Overlay
          Positioned(
            top: 14,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(Icons.radar_rounded,
                      size: 14, color: AppColors.secondaryBlue),
                  SizedBox(width: 6),
                  Text(
                    'LIVE SATELLITE & RADIO MESH BEACON',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondaryBlue,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Coordinates Overlay
          Positioned(
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.secondaryBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                em.hasValidCoordinates
                    ? 'TARGET FIX: ${em.latitude.toStringAsFixed(5)}°N, ${em.longitude.toStringAsFixed(5)}°E'
                    : 'TARGET FIX: Location Unavailable',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: AppColors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
