import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../shared/widgets/connectivity_banner.dart';
import 'widgets/logged_in_sos_section.dart';

export 'widgets/logged_in_sos_section.dart';

class EmergencyTypeScreen extends StatelessWidget {
  final EmergencyType? initialType;

  const EmergencyTypeScreen({super.key, this.initialType});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('SOS Emergency Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Real-Time Telemetry & Connectivity Banner
              const ConnectivityBanner(),

              const SizedBox(height: 16),

              LoggedInSosSection(initialType: initialType),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
