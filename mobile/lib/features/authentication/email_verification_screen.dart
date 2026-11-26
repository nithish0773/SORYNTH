import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';

/// Screen displayed when a user registers with email/password and must
/// confirm their email address before logging in to SORYNTH.
class EmailVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const EmailVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  bool _isResending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _cooldownSeconds = seconds;
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _cooldownSeconds = 0;
        });
      } else {
        setState(() {
          _cooldownSeconds--;
        });
      }
    });
  }

  Future<void> _handleResend() async {
    if (_isResending || _cooldownSeconds > 0) return;

    final emailToUse = widget.email.trim();
    if (emailToUse.isEmpty || !emailToUse.contains('@')) {
      setState(() {
        _isSuccess = false;
        _statusMessage =
            'A valid email address is required to resend verification.';
      });
      return;
    }

    setState(() {
      _isResending = true;
      _statusMessage = null;
    });

    try {
      final supabase = ref.read(supabaseServiceProvider);
      if (!supabase.isConfigured) {
        throw Exception(
            'Authentication service is currently unavailable. Please check your network.');
      }

      await supabase.resendConfirmationEmail(emailToUse);

      if (mounted) {
        setState(() {
          _isSuccess = true;
          _statusMessage =
              'Verification email sent! Please check your inbox and spam folder.';
        });
        _startCooldown(60);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final isRateLimit = e.statusCode == '429' ||
          e.code == 'over_email_send_rate_limit' ||
          msg.contains('rate limit') ||
          msg.contains('too many requests');

      setState(() {
        _isSuccess = false;
        if (isRateLimit) {
          _startCooldown(60);
          _statusMessage =
              'Too many requests. Please wait a moment before requesting another verification email.';
        } else {
          _statusMessage = e.message.isNotEmpty
              ? e.message
              : 'Could not resend verification email.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      final str = e.toString().toLowerCase();
      final isNetwork = str.contains('socket') ||
          str.contains('clientexception') ||
          str.contains('failed host lookup') ||
          str.contains('network') ||
          str.contains('timeout') ||
          str.contains('connection');

      setState(() {
        _isSuccess = false;
        _statusMessage = isNetwork
            ? 'Network error. Please check your internet connection and try again.'
            : 'Could not send verification email. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final scaffoldBg =
        isDark ? AppColors.darkBackground : AppColors.background;
    final cardBg = isDark ? AppColors.darkCardSurface : AppColors.white;
    final cardBorder = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryText =
        isDark ? AppColors.darkPrimaryText : AppColors.textDark;
    final secondaryText =
        isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    final displayEmail = widget.email.trim().isNotEmpty
        ? widget.email.trim()
        : 'your registered email';

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: primaryText,
            size: 20,
          ),
          tooltip: 'Back to Sign In',
          onPressed: () => context.go(AppRoutes.login),
        ),
        title: Text(
          'Email Verification',
          style: TextStyle(
            color: primaryText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Verification Illustration / Badge
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primaryBlue,
                          AppColors.secondaryBlue,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mark_email_unread_rounded,
                        color: AppColors.white,
                        size: 48,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Heading
                  Text(
                    'Verify Your Email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: primaryText,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Subtitle
                  Text(
                    'A verification link has been sent to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: secondaryText,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Registered Email Address Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.mail_rounded,
                          size: 20,
                          color: AppColors.primaryBlue,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            displayEmail,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.white
                                  : AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Steps Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next Steps:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStepRow(
                          number: '1',
                          text: 'Open your email application or inbox.',
                          primaryText: primaryText,
                          secondaryText: secondaryText,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _buildStepRow(
                          number: '2',
                          text:
                              'Click the verification link from SORYNTH to confirm your address.',
                          primaryText: primaryText,
                          secondaryText: secondaryText,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        _buildStepRow(
                          number: '3',
                          text:
                              'Return to SORYNTH and sign in to access full emergency features.',
                          primaryText: primaryText,
                          secondaryText: secondaryText,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        Divider(color: cardBorder, height: 1),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: secondaryText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Don't see the email? Check your spam or junk folder.",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: secondaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status Message Banner (Success / Error)
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _isSuccess
                            ? AppColors.successGreen.withValues(alpha: 0.12)
                            : AppColors.emergencyRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isSuccess
                              ? AppColors.successGreen.withValues(alpha: 0.5)
                              : AppColors.emergencyRed.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isSuccess
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: 20,
                            color: _isSuccess
                                ? AppColors.successGreen
                                : AppColors.emergencyRed,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isSuccess
                                    ? AppColors.successGreen
                                    : AppColors.emergencyRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Resend Verification Email Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: (_isResending || _cooldownSeconds > 0)
                          ? null
                          : _handleResend,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                        side: BorderSide(
                          color: (_isResending || _cooldownSeconds > 0)
                              ? (isDark
                                  ? AppColors.darkBorder
                                  : AppColors.borderLight)
                              : AppColors.primaryBlue,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: isDark
                            ? AppColors.darkCardSurface
                            : AppColors.white,
                      ),
                      icon: _isResending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primaryBlue,
                                ),
                              ),
                            )
                          : Icon(
                              _cooldownSeconds > 0
                                  ? Icons.timer_outlined
                                  : Icons.send_rounded,
                              size: 18,
                              color: (_isResending || _cooldownSeconds > 0)
                                  ? secondaryText
                                  : AppColors.primaryBlue,
                            ),
                      label: Text(
                        _isResending
                            ? 'Resending...'
                            : (_cooldownSeconds > 0
                                ? 'Resend in ${_cooldownSeconds}s'
                                : 'Resend Verification Email'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: (_isResending || _cooldownSeconds > 0)
                              ? secondaryText
                              : AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Return to Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => context.go(AppRoutes.login),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: AppColors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Back to Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Change Email option
                  Center(
                    child: TextButton(
                      onPressed: () => context.go(AppRoutes.register),
                      child: Text(
                        'Entered wrong email? Register again',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: secondaryText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow({
    required String number,
    required String text,
    required Color primaryText,
    required Color secondaryText,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? AppColors.darkBorder
                : AppColors.primaryBlue.withValues(alpha: 0.12),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.white : AppColors.primaryBlue,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: primaryText,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
