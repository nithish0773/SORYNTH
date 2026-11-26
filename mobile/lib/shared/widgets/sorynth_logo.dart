import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class SorynthLogo extends StatelessWidget {
  final double size;
  final bool isDarkBackground;
  final bool showText;

  const SorynthLogo({
    super.key,
    this.size = 80,
    this.isDarkBackground = false,
    this.showText = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark =
        isDarkBackground || Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primaryBlue, AppColors.secondaryBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.35),
                blurRadius: size * 0.25,
                offset: Offset(0, size * 0.08),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.cell_tower_rounded,
              color: AppColors.white,
              size: size * 0.52,
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 16),
          Text(
            'SORYNTH',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.0,
              color: isDark ? AppColors.white : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'SIGNAL BEYOND BOUNDARIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: isDark
                  ? AppColors.secondaryBlue
                  : AppColors.primaryBlue,
            ),
          ),
        ],
      ],
    );
  }
}

