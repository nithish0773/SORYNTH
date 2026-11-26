import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routing/app_router.dart';
import '../../../data/models/emergency_model.dart';
import '../../../shared/widgets/sos_button.dart';

class LoggedInSosSection extends ConsumerStatefulWidget {
  final EmergencyType? initialType;

  const LoggedInSosSection({super.key, this.initialType});

  @override
  ConsumerState<LoggedInSosSection> createState() => _LoggedInSosSectionState();
}

class _LoggedInSosSectionState extends ConsumerState<LoggedInSosSection> {
  EmergencyType? _selectedType;
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();
  bool _isDispatching = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
  }

  @override
  void didUpdateWidget(covariant LoggedInSosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialType != oldWidget.initialType && widget.initialType != null) {
      _selectedType = widget.initialType;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  String _generateEmergencyCode() {
    final rand = Random().nextInt(900000) + 100000;
    return 'SOR$rand';
  }

  IconData _getCategoryIcon(EmergencyType? type) {
    if (type == null) return Icons.crisis_alert_rounded;
    switch (type) {
      case EmergencyType.medical:
        return Icons.local_hospital_rounded;
      case EmergencyType.accident:
        return Icons.car_crash_rounded;
      case EmergencyType.fire:
        return Icons.local_fire_department_rounded;
      case EmergencyType.naturalDisaster:
        return Icons.tsunami_rounded;
      case EmergencyType.lostStranded:
        return Icons.explore_off_rounded;
      case EmergencyType.other:
        return Icons.warning_rounded;
    }
  }

  void _dispatchSos() {
    if (_isDispatching) return;

    final trimmedDescription = _descriptionController.text.trim();

    setState(() {
      _isDispatching = true;
    });

    try {
      final gpsState = ref.read(gpsNotifierProvider).value;
      final userProfile = ref.read(userProfileProvider);
      final supabase = ref.read(supabaseServiceProvider);
      final storage = ref.read(offlineStorageServiceProvider);

      final bool hasGps = gpsState?.isSuccess == true;
      final double lat = hasGps ? gpsState!.latitude : 0.0;
      final double lng = hasGps ? gpsState!.longitude : 0.0;
      final double? acc = hasGps ? gpsState!.accuracy : null;

      final user = supabase.currentUser;
      final resolvedPersonId = user?.id ?? storage.getOrCreateGuestId();
      final profileName = userProfile?.fullName.trim();
      final resolvedPersonName = (profileName != null && profileName.isNotEmpty)
          ? profileName
          : (user?.email ?? 'Civilian SOS Caller');

      // Case 1: Urgent SOS without category -> URGENT / UNSPECIFIED
      // Case 2: Categorized SOS -> selected category
      final resolvedType = _selectedType ?? EmergencyType.other;

      // Description is optional; fallback to standard emergency alert message
      final finalMessage = trimmedDescription.isNotEmpty
          ? trimmedDescription
          : (_selectedType == null
              ? 'Emergency Alert: URGENT / UNSPECIFIED'
              : 'Emergency Alert: ${resolvedType.label}');

      final emergency = EmergencyModel(
        emergencyId: _generateEmergencyCode(),
        personId: resolvedPersonId,
        personName: resolvedPersonName,
        phone: userProfile?.phoneNumber ?? user?.phone,
        latitude: lat,
        longitude: lng,
        accuracy: acc,
        emergencyType: resolvedType,
        message: finalMessage,
        communicationMethod: CommunicationMethod.internet,
        status: EmergencyStatus.pending,
        timestamp: DateTime.now(),
        isGuest: user == null,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final cardBorder = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryText = isDark ? AppColors.darkPrimaryText : AppColors.textDark;
    final secondaryText = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Existing HOLD SOS Button Card (at top of page)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : AppColors.cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emergency_rounded,
                    color: AppColors.emergencyRed,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'HOLD SOS TO TRANSMIT',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: primaryText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                    Icon(
                      _getCategoryIcon(_selectedType),
                      color: AppColors.emergencyRed,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _selectedType != null
                            ? 'Selected: ${_selectedType!.label}'
                            : 'Category: URGENT / UNSPECIFIED',
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
              const SizedBox(height: 8),
              // Responsive Hold SOS Button - Automatic Dispatch upon Hold Completion
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = (constraints.maxWidth * 0.58).clamp(150.0, 185.0);
                  return SosButton(
                    size: size,
                    holdDuration: const Duration(milliseconds: 1500),
                    onTriggered: _dispatchSos,
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Press and hold for 1.5s to transmit',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: secondaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Releasing early cancels transmission without alert creation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryText.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 2. Emergency Category Selection (below SOS Button)
        Row(
          children: [
            const Icon(
              Icons.category_rounded,
              size: 20,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Select Emergency Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: primaryText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Optionally select a crisis category to route your alert to specialized rescue teams, or hold SOS above for immediate urgent dispatch.',
          style: TextStyle(
            fontSize: 12,
            color: secondaryText,
            height: 1.3,
          ),
        ),

        const SizedBox(height: 12),

        _buildCategorySelector(isDark, cardBg, cardBorder, primaryText),

        const SizedBox(height: 24),

        // 3. Optional Victim Description text field
        Row(
          children: [
            const Icon(
              Icons.edit_note_rounded,
              size: 22,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Situation & Victim Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: primaryText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.chipBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cardBorder),
              ),
              child: Text(
                'OPTIONAL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: secondaryText,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Provide specific situation details, number of victims, immediate needs, or structural hazards (optional).',
          style: TextStyle(
            fontSize: 12,
            color: secondaryText,
            height: 1.3,
          ),
        ),

        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.25) : AppColors.cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: _descriptionController,
            focusNode: _descriptionFocusNode,
            minLines: 4,
            maxLines: 7,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: TextStyle(
              fontSize: 14,
              color: primaryText,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Describe situation details (e.g. 3 injured, severe bleeding, trapped under fallen debris, need stretcher)...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkSecondaryText : AppColors.textMuted,
                height: 1.4,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: secondaryText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your exact coordinates and description (if provided) will be forwarded to rescue teams over internet or LoRa mesh.',
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryText,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategorySelector(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color primaryText,
  ) {
    const types = [
      EmergencyType.medical,
      EmergencyType.accident,
      EmergencyType.fire,
      EmergencyType.naturalDisaster,
      EmergencyType.lostStranded,
      EmergencyType.other,
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
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
          onTap: () {
            setState(() {
              if (_selectedType == type) {
                _selectedType = null;
              } else {
                _selectedType = type;
              }
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: isDark ? 0.22 : 0.12)
                  : cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : cardBorder,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.2)
                            : AppColors.cardShadow,
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? color : primaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: color,
                    size: 16,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
