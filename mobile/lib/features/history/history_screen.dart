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

enum HistoryFilter { all, active, resolved }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryFilter _filter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final cardBorder = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryText = isDark ? AppColors.darkPrimaryText : AppColors.textDark;
    final secondaryText = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    final emergencies = ref.watch(emergencyHistoryProvider);

    final filteredList = emergencies.where((em) {
      if (_filter == HistoryFilter.active) {
        return em.status != EmergencyStatus.resolved &&
            em.status != EmergencyStatus.cancelled;
      } else if (_filter == HistoryFilter.resolved) {
        return em.status == EmergencyStatus.resolved ||
            em.status == EmergencyStatus.cancelled;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('SOS History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Selector
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All Alerts', HistoryFilter.all, isDark, cardBg, cardBorder, primaryText, secondaryText),
                    const SizedBox(width: 8),
                    _buildFilterChip('Active Only', HistoryFilter.active, isDark, cardBg, cardBorder, primaryText, secondaryText),
                    const SizedBox(width: 8),
                    _buildFilterChip('Resolved', HistoryFilter.resolved, isDark, cardBg, cardBorder, primaryText, secondaryText),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // List of SOS emergencies
            Expanded(
              child: filteredList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_toggle_off_rounded,
                            size: 64,
                            color: secondaryText.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _filter == HistoryFilter.active
                                ? 'No active emergencies'
                                : 'No emergency logs recorded yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: secondaryText,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final em = filteredList[index];
                        return _buildEmergencyCard(em, isDark, cardBg, cardBorder, primaryText, secondaryText);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    HistoryFilter filter,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color primaryText,
    Color secondaryText,
  ) {
    final isSelected = _filter == filter;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _filter = filter);
      },
      selectedColor: AppColors.primaryBlue,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isSelected ? AppColors.white : primaryText,
      ),
      backgroundColor: cardBg,
      side: BorderSide(
        color: isSelected ? AppColors.primaryBlue : cardBorder,
      ),
    );
  }

  Widget _buildEmergencyCard(
    EmergencyModel em,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color primaryText,
    Color secondaryText,
  ) {
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(em.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          context.push(AppRoutes.sosActive, extra: em);
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.emergency_rounded,
                            size: 16,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            em.emergencyId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: primaryText,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: StatusBadge(status: em.status, isCompact: true),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                em.emergencyType.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14, color: secondaryText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      em.hasValidCoordinates
                          ? '${em.latitude.toStringAsFixed(4)}°N, ${em.longitude.toStringAsFixed(4)}°E (±${em.accuracy?.round() ?? 0}m)'
                          : 'Location Unavailable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.alt_route_rounded,
                      size: 14, color: secondaryText),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${em.communicationMethod.displayName} • ${em.hopCount} hops',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 20, color: cardBorder),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      dateStr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: AppColors.primaryBlue),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

