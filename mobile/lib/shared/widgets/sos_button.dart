import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

class SosButton extends StatefulWidget {
  final VoidCallback onTriggered;
  final double size;
  final Duration holdDuration;
  final VoidCallback? onTap;
  final String? label;
  final String? sublabel;

  const SosButton({
    super.key,
    required this.onTriggered,
    this.size = 200,
    this.holdDuration = const Duration(seconds: 2),
    this.onTap,
    this.label,
    this.sublabel,
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHolding = false;

  String get _displayLabel {
    if (_isHolding) return 'HOLDING...';
    if (widget.label != null) return widget.label!;
    if (widget.onTap != null) return 'SELECT CATEGORY';
    if (widget.holdDuration.inMilliseconds == 2000) return 'HOLD 2s';
    if (widget.holdDuration.inMilliseconds % 1000 == 0) {
      return 'HOLD ${widget.holdDuration.inSeconds}s';
    }
    return 'HOLD ${(widget.holdDuration.inMilliseconds / 1000.0).toStringAsFixed(1)}s';
  }

  String get _displaySublabel {
    if (_isHolding) return 'Keep holding to broadcast...';
    if (widget.sublabel != null) return widget.sublabel!;
    if (widget.onTap != null) return 'Tap to select category & hold SOS';
    return 'Press & hold to activate alert';
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          HapticFeedback.heavyImpact();
          _isHolding = false;
          _controller.reset();
          widget.onTriggered();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) return;
    setState(() => _isHolding = true);
    HapticFeedback.mediumImpact();
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) return;
    _cancelHold();
  }

  void _onTapCancel() {
    if (widget.onTap != null) return;
    _cancelHold();
  }

  void _cancelHold() {
    if (_isHolding) {
      setState(() => _isHolding = false);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onTap,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final scale = 1.0 - (_controller.value * 0.05);
              return Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer Pulse Ring
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isHolding
                              ? AppColors.emergencyRed.withValues(alpha: 0.2)
                              : AppColors.emergencyRed.withValues(alpha: 0.08),
                        ),
                      ),

                      // Progress Ring
                      SizedBox(
                        width: widget.size - 10,
                        height: widget.size - 10,
                        child: CircularProgressIndicator(
                          value: _controller.value,
                          strokeWidth: 6,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.emergencyRed,
                          ),
                        ),
                      ),

                      // Main SOS Core Button
                      Container(
                        width: widget.size - 30,
                        height: widget.size - 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.emergencyRed,
                              AppColors.emergencyRedHover,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.emergencyRed.withValues(alpha: 0.4),
                              blurRadius: _isHolding ? 35 : 20,
                              spreadRadius: _isHolding ? 4 : 2,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.emergency_rounded,
                              color: AppColors.white,
                              size: (widget.size * 0.18).clamp(22.0, 48.0),
                            ),
                            SizedBox(height: widget.size >= 160 ? 4 : 2),
                            Text(
                              'SOS',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: (widget.size * 0.17).clamp(20.0, 44.0),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                            ),
                            SizedBox(height: widget.size >= 160 ? 3 : 1),
                            Text(
                              _displayLabel,
                              style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.85),
                                fontSize: (widget.size * 0.055).clamp(9.0, 14.0),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: widget.size >= 160 ? 16 : 8),
        Builder(
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final chipBg = isDark ? AppColors.darkCardSurface : AppColors.white;
            final borderColor =
                isDark ? AppColors.darkBorder : AppColors.borderLight;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: chipBg,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 16,
                    color: _isHolding
                        ? AppColors.emergencyRed
                        : (isDark
                            ? AppColors.darkSecondaryText
                            : AppColors.secondaryText),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _displaySublabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isHolding
                            ? AppColors.emergencyRed
                            : (isDark
                                ? AppColors.darkSecondaryText
                                : AppColors.secondaryText),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

