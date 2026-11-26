import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/emergency_model.dart';
import '../../data/services/gps_service.dart';
import '../../shared/widgets/connectivity_banner.dart';
import '../../shared/widgets/sos_button.dart';
import '../../shared/widgets/sorynth_logo.dart';
import '../../shared/widgets/status_badge.dart';

class GuestSosScreen extends ConsumerStatefulWidget {
  const GuestSosScreen({super.key});

  @override
  ConsumerState<GuestSosScreen> createState() => _GuestSosScreenState();
}

class _GuestSosScreenState extends ConsumerState<GuestSosScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  EmergencyType _selectedType = EmergencyType.medical;
  bool _isDispatching = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateEmergencyCode() {
    final rand = Random().nextInt(900000) + 100000;
    return 'SOR$rand';
  }

  void _triggerGuestSos() {
    if (_isDispatching) return;

    final notes = _notesController.text.trim();
    if (_selectedType == EmergencyType.other && notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please describe the emergency situation when "Other" is selected.',
          ),
          backgroundColor: AppColors.emergencyRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isDispatching = true);

    try {
      final gpsState = ref.read(gpsNotifierProvider).value;
      final bool hasGps = gpsState?.isSuccess == true;
      final double lat = hasGps ? gpsState!.latitude : 0.0;
      final double lng = hasGps ? gpsState!.longitude : 0.0;
      final double? acc = hasGps ? gpsState!.accuracy : null;

      final storage = ref.read(offlineStorageServiceProvider);
      final guestId = storage.getOrCreateGuestId();
      final code = _generateEmergencyCode();
      final personName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : 'Civilian Guest';

      final emergency = EmergencyModel(
        emergencyId: code,
        personId: guestId,
        personName: personName,
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        latitude: lat,
        longitude: lng,
        accuracy: acc,
        emergencyType: _selectedType,
        message: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : 'Emergency SOS: ${_selectedType.label}',
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.pending,
        timestamp: DateTime.now(),
        isGuest: true,
      );

      context.push(AppRoutes.sosSending, extra: emergency).then((_) {
        if (mounted) {
          setState(() {
            _isDispatching = false;
          });
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isDispatching = false;
        });
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[GuestSosScreen] build() executed');
    final gpsAsync = ref.watch(gpsNotifierProvider);
    final activeEmergency = ref.watch(activeEmergencyProvider);
    final isEmergencyActive =
        activeEmergency != null && activeEmergency.isGenuinelyActive;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primaryTextColor),
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
                      color: primaryTextColor,
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
        leading: (GoRouter.maybeOf(context)?.canPop() ?? false)
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: primaryTextColor,
                ),
                tooltip: 'Back',
                onPressed: () => context.pop(),
              )
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: TextButton.icon(
              onPressed: () => context.push(AppRoutes.welcome),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                backgroundColor: AppColors.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  ),
                ),
              ),
              icon: const Icon(
                Icons.login_rounded,
                size: 18,
                color: AppColors.primaryBlue,
              ),
              label: const Text(
                'Sign In',
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Emergency Resume Banner (if any active)
              if (isEmergencyActive) ...[
                _buildActiveEmergencyBanner(context, activeEmergency, primaryTextColor),
                const SizedBox(height: 10),
              ],

              // Connectivity Status Banner
              const ConnectivityBanner(),

              const SizedBox(height: 8),

              // GPS Location Card
              _buildGpsCard(gpsAsync),

              const SizedBox(height: 8),

              // Selected Category Confirmation Display
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.emergencyRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.emergencyRed.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.crisis_alert_rounded,
                        color: AppColors.emergencyRed,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Category: ${_selectedType.label}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.emergencyRed,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Large, Centered Hero SOS Press-and-Hold Button (Responsive clamp, visual center)
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final buttonSize =
                      (availableWidth * 0.62).clamp(170.0, 220.0);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: SosButton(
                        size: buttonSize,
                        holdDuration: const Duration(milliseconds: 1500),
                        onTriggered: _triggerGuestSos,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              // Urgent Notice Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.emergencyRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.emergencyRed.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      color: AppColors.emergencyRed,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No registration required. Your emergency and GPS coordinates will be sent immediately to rescue units.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.emergencyRed,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Emergency Type Selection
              Text(
                'Select Emergency Type *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 10),

              _buildEmergencyTypeSelector(),

              const SizedBox(height: 20),

              // Optional Civilian Information Card
              Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.person_pin_circle_outlined,
                          size: 20,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sender Information (Optional)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: primaryTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your Name (Optional)',
                        hintText: 'e.g. Rahul Verma',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact Number (Optional)',
                        hintText: 'Enter Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Additional Situation Notes (Optional)',
                        hintText: 'e.g. 2 people injured, trapped under debris',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Quick Actions: Guest SOS History & Settings
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.history),
                      icon: Icon(Icons.history_rounded, size: 18, color: primaryTextColor),
                      label: Text(
                        'SOS History',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.settings),
                      icon: Icon(Icons.settings_outlined, size: 18, color: primaryTextColor),
                      label: Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsCard(AsyncValue<dynamic> gpsAsync) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor =
        isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: gpsAsync.when(
        data: (gps) {
          final isSuccess = gps.isSuccess;
          return Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSuccess
                      ? AppColors.primaryBlue.withValues(alpha: 0.1)
                      : AppColors.warningYellow.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess
                      ? Icons.location_on_rounded
                      : Icons.location_searching_rounded,
                  color: isSuccess
                      ? AppColors.primaryBlue
                      : AppColors.warningYellow,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSuccess ? gps.qualityBadgeLabel : 'Searching for GPS Fix...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSuccess
                          ? '${gps.latitude.toStringAsFixed(5)}, ${gps.longitude.toStringAsFixed(5)} (±${gps.accuracy.round()}m)'
                          : 'Ensure device location services are turned on',
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                      ),
                    ),
                    if (isSuccess && gps.quality == GpsQuality.approximate) ...[
                      const SizedBox(height: 4),
                      const Text(
                        '⚠️ Approximate location fix (>30m). High-accuracy satellite lock acquiring.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warningYellow,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryBlue),
                tooltip: 'Refresh Location',
                onPressed: () {
                  ref.read(gpsNotifierProvider.notifier).refreshLocation();
                },
              ),
            ],
          );
        },
        loading: () => Row(
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Locking current GPS coordinates...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
              ),
            ),
          ],
        ),
        error: (err, _) => Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.emergencyRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'GPS Error: $err',
                style: const TextStyle(fontSize: 12, color: AppColors.emergencyRed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyTypeSelector() {
    final types = EmergencyType.values;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 500 ? 3 : 2;
        final cardHeight = constraints.maxWidth > 500 ? 54.0 : 48.0;
        final cardWidth =
            (constraints.maxWidth - ((crossAxisCount - 1) * 8)) /
                crossAxisCount;
        final aspectRatio = (cardWidth / cardHeight).clamp(1.8, 3.8);

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: aspectRatio,
          ),
          itemCount: types.length,
          itemBuilder: (context, index) {
            final type = types[index];
            final isSelected = _selectedType == type;

            IconData icon;
            Color color;

            switch (type) {
              case EmergencyType.medical:
                icon = Icons.local_hospital_rounded;
                color = AppColors.emergencyRed;
                break;
              case EmergencyType.accident:
                icon = Icons.car_crash_rounded;
                color = const Color(0xFFF97316);
                break;
              case EmergencyType.fire:
                icon = Icons.local_fire_department_rounded;
                color = const Color(0xFFEF4444);
                break;
              case EmergencyType.naturalDisaster:
                icon = Icons.tsunami_rounded;
                color = const Color(0xFF0284C7);
                break;
              case EmergencyType.lostStranded:
                icon = Icons.explore_off_rounded;
                color = const Color(0xFF8B5CF6);
                break;
              case EmergencyType.other:
                icon = Icons.warning_rounded;
                color = const Color(0xFF64748B);
                break;
            }

            return InkWell(
              onTap: () => setState(() => _selectedType = type),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: isDark ? 0.22 : 0.12)
                      : cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? color : borderColor,
                    width: isSelected ? 2.0 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : (isDark
                          ? const []
                          : const [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ]),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 17),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? color : primaryTextColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveEmergencyBanner(
      BuildContext context, EmergencyModel emergency, Color primaryTextColor) {
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
                      StatusBadge(status: emergency.status, isCompact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${emergency.emergencyType.label} • Tap to view tracking & telemetry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: primaryTextColor,
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
}

