import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/emergency_model.dart';
import '../../data/repositories/emergency_repository.dart';
import '../../shared/widgets/status_badge.dart';

class SosSendingScreen extends ConsumerStatefulWidget {
  final EmergencyModel? emergency;

  const SosSendingScreen({
    super.key,
    required this.emergency,
  });

  @override
  ConsumerState<SosSendingScreen> createState() => _SosSendingScreenState();
}

class _SosSendingScreenState extends ConsumerState<SosSendingScreen> {
  EmergencyModel? _currentEmergency;
  List<SosTransmissionStep> _steps = [];
  StreamSubscription? _dispatchSubscription;
  StreamSubscription<EmergencyModel>? _emergencyUpdatesSub;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _currentEmergency = widget.emergency;

    final repo = ref.read(emergencyRepositoryProvider);
    final targetId =
        widget.emergency?.emergencyId ?? repo.getActiveEmergencyId();
    if (targetId != null) {
      final stored = repo.getEmergency(targetId);
      if (stored != null) {
        _currentEmergency = stored;
      }
    }

    if (_currentEmergency == null) {
      // Fallback if accessed directly
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (ref.read(supabaseServiceProvider).currentUser != null) {
            context.go(AppRoutes.home);
          } else {
            context.go(AppRoutes.guestSos);
          }
        }
      });
      return;
    }

    if (_currentEmergency!.isServerConfirmed) {
      _steps = repo.getPipelineSteps(_currentEmergency!);
      _isFinished = true;
    } else {
      _startDispatch();
    }

    _listenForEmergencyUpdates();
  }

  void _listenForEmergencyUpdates() {
    final repo = ref.read(emergencyRepositoryProvider);
    _emergencyUpdatesSub = repo.emergencyUpdatesStream.listen((updated) {
      if (mounted && updated.emergencyId == _currentEmergency?.emergencyId) {
        setState(() {
          _currentEmergency = updated;
          if (updated.isServerConfirmed) {
            _steps = repo.getPipelineSteps(updated);
            _isFinished = true;
          }
        });
      }
    });
  }

  void _startDispatch() {
    final repo = ref.read(emergencyRepositoryProvider);
    HapticFeedback.heavyImpact();

    _dispatchSubscription = repo
        .dispatchEmergency(
      emergency: _currentEmergency!,
      onEmergencyUpdated: (updated) {
        if (mounted) {
          setState(() {
            _currentEmergency = updated;
          });
          ref.read(activeEmergencyProvider.notifier).setActive(updated);
          ref.read(emergencyHistoryProvider.notifier).refresh();
        }
      },
    )
        .listen((steps) {
      if (mounted) {
        setState(() {
          _steps = steps;
        });

        // Check if finished (either internet success, BLE/LoRa completed, or BLE blocked)
        final isInternetDone = steps.length > 3 && steps[3].isCompleted;
        final isBleDone = steps.length > 5 && (steps[5].isCompleted || steps[5].isFailed);
        final isBleBlocked = steps.length > 4 && steps[4].isFailed;

        if (isInternetDone || isBleDone || isBleBlocked) {
          setState(() => _isFinished = true);
        }
      }
    });
  }

  @override
  void dispose() {
    _dispatchSubscription?.cancel();
    _emergencyUpdatesSub?.cancel();
    super.dispose();
  }

  void _navigateToTracking() {
    if (_currentEmergency != null) {
      context.go(AppRoutes.sosActive, extra: _currentEmergency);
    } else {
      if (ref.read(supabaseServiceProvider).currentUser != null) {
        context.go(AppRoutes.home);
      } else {
        context.go(AppRoutes.guestSos);
      }
    }
  }

  Future<void> _confirmCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Emergency Transmission?'),
        content: const Text(
          'Are you sure you want to abort the distress broadcast? Rescue teams will not be alerted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue Sending'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergencyRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Alert'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      _dispatchSubscription?.cancel();
      if (_currentEmergency != null) {
        await ref
            .read(emergencyRepositoryProvider)
            .cancelEmergency(_currentEmergency!.emergencyId);
      }
      if (mounted) {
        if (_currentEmergency?.isGuest == true ||
            ref.read(supabaseServiceProvider).currentUser == null) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.guestSos);
          }
        } else {
          context.go(AppRoutes.home);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(emergencyRepositoryProvider);
    ref.listen<EmergencyModel?>(activeEmergencyProvider, (prev, next) {
      if (next != null && next.emergencyId == _currentEmergency?.emergencyId) {
        if (mounted) {
          setState(() {
            _currentEmergency = next;
            if (next.isServerConfirmed) {
              _steps = repo.getPipelineSteps(next);
              _isFinished = true;
            }
          });
        }
      }
    });

    if (_currentEmergency == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final em = _currentEmergency!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final cardBorder = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryText = isDark ? AppColors.darkPrimaryText : AppColors.textDark;
    final secondaryText = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            'SOS BROADCAST • ${em.emergencyId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _confirmCancel,
              child: const Text(
                'Abort',
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
          child: Column(
            children: [
              // Emergency Info Header Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withValues(alpha: 0.25) : AppColors.cardShadow,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.emergencyRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.emergency_rounded,
                        color: AppColors.emergencyRed,
                        size: 26,
                      ),
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
                                em.emergencyType.label,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: primaryText,
                                ),
                              ),
                              StatusBadge(
                                status: em.status,
                                isCompact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            em.hasValidCoordinates
                                ? 'Sender: ${em.personName} • Lat: ${em.latitude.toStringAsFixed(4)}, Lng: ${em.longitude.toStringAsFixed(4)} (${em.accuracyQualityLabel})'
                                : 'Sender: ${em.personName} • Location: Unavailable',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Steps Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.alt_route_rounded,
                        size: 18, color: AppColors.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Transmission Pipeline Telemetry',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: primaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Steps List
              Expanded(
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    final step = _steps[index];
                    return _buildStepTile(step, isDark, cardBg, cardBorder, primaryText, secondaryText);
                  },
                ),
              ),

              // Bottom Control
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    if (_isFinished) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: em.isServerConfirmed
                              ? AppColors.successGreen.withValues(alpha: 0.1)
                              : (em.status == EmergencyStatus.gatewayReceived
                                  ? AppColors.secondaryBlue.withValues(alpha: 0.1)
                                  : AppColors.warningYellow.withValues(alpha: 0.12)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: em.isServerConfirmed
                                ? AppColors.successGreen.withValues(alpha: 0.3)
                                : (em.status == EmergencyStatus.gatewayReceived
                                    ? AppColors.secondaryBlue.withValues(alpha: 0.3)
                                    : AppColors.warningYellow.withValues(alpha: 0.3)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              em.isServerConfirmed
                                  ? Icons.cloud_done_rounded
                                  : (em.status == EmergencyStatus.gatewayReceived
                                      ? Icons.router_rounded
                                      : Icons.inventory_2_rounded),
                              size: 18,
                              color: em.isServerConfirmed
                                  ? AppColors.successGreen
                                  : (em.status == EmergencyStatus.gatewayReceived
                                      ? AppColors.secondaryBlue
                                      : AppColors.warningYellow),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                em.isServerConfirmed
                                    ? 'Delivered Successfully'
                                    : em.deliveryStatusLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: em.isServerConfirmed
                                      ? AppColors.successGreen
                                      : (em.status == EmergencyStatus.gatewayReceived
                                          ? AppColors.secondaryBlue
                                          : AppColors.textDark),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _navigateToTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'View Live SOS Tracking & Telemetry',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ]
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Awaiting verified delivery confirmation...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepTile(
    SosTransmissionStep step,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color primaryText,
    Color secondaryText,
  ) {
    Widget leadingWidget;

    if (step.isCompleted) {
      leadingWidget = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.successGreen.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            color: AppColors.successGreen, size: 18),
      );
    } else if (step.isFailed) {
      leadingWidget = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.warningYellow.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.priority_high_rounded,
            color: AppColors.warningYellow, size: 16),
      );
    } else if (step.isInProgress) {
      leadingWidget = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    } else {
      leadingWidget = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBorder : AppColors.borderLight,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${step.stepNumber}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: secondaryText,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: step.isInProgress
              ? AppColors.primaryBlue.withValues(alpha: 0.5)
              : cardBorder,
          width: step.isInProgress ? 1.5 : 1.0,
        ),
        boxShadow: step.isInProgress
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leadingWidget,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: step.isInProgress
                        ? AppColors.primaryBlue
                        : primaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  step.detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryText,
                    height: 1.3,
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
