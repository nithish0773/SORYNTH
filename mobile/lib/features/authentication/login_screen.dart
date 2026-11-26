import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/routing/app_router.dart';
import '../../shared/widgets/google_logo.dart';
import '../../shared/widgets/sorynth_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isEmailUnconfirmed = false;
  bool _isResendingEmail = false;
  int _resendCooldownSeconds = 0;
  Timer? _resendTimer;
  String? _errorMessage;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen for auth state transitions (such as successful OAuth deep link return)
    final supabase = ref.read(supabaseServiceProvider);
    _authSubscription = supabase.authStateChanges?.listen((data) async {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        try {
          await supabase.syncOAuthProfile(data.session!.user);
          await ref.read(userProfileProvider.notifier).loadProfile();
          if (mounted) {
            context.go(AppRoutes.home);
          }
        } catch (e) {
          debugPrint('[LoginScreen] Error synchronizing session: $e');
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app resumes after launching the external browser for Google OAuth,
    // if no session was established (e.g. user cancelled or closed browser),
    // immediately re-enable the Google login button.
    if (state == AppLifecycleState.resumed && _isGoogleLoading) {
      final supabase = ref.read(supabaseServiceProvider);
      if (supabase.currentUser == null) {
        if (mounted) {
          setState(() => _isGoogleLoading = false);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 60]) {
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _resendCooldownSeconds = seconds;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _resendCooldownSeconds = 0;
        });
      } else {
        setState(() {
          _resendCooldownSeconds--;
        });
      }
    });
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.welcome);
    }
  }

  Future<void> _handleLogin() async {
    if (_isLoading || _isGoogleLoading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isEmailUnconfirmed = false;
    });

    try {
      final supabase = ref.read(supabaseServiceProvider);

      if (!supabase.isConfigured) {
        throw Exception(
            'Authentication service is currently unavailable. Please check your network and configuration.');
      }

      await supabase.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );

      await ref.read(userProfileProvider.notifier).loadProfile();

      if (mounted) {
        context.go(AppRoutes.home);
      }
    } on AuthException catch (e) {
      final msg = e.message;
      final code = (e.code ?? '').toLowerCase();
      final msgLower = msg.toLowerCase();

      final isUnconfirmed = code == 'email_not_confirmed' ||
          msgLower.contains('email not confirmed');
      final isInvalidCreds = code == 'invalid_credentials' ||
          code == 'invalid_grant' ||
          msgLower.contains('invalid login credentials') ||
          msgLower.contains('invalid credentials') ||
          msgLower.contains('invalid email or password');
      final isRateLimit = e.statusCode == '429' ||
          code == 'over_email_send_rate_limit' ||
          msgLower.contains('rate limit');
      final isNetwork = msgLower.contains('network') ||
          msgLower.contains('socket') ||
          msgLower.contains('failed host lookup') ||
          msgLower.contains('timeout') ||
          msgLower.contains('connection');

      setState(() {
        _isEmailUnconfirmed = isUnconfirmed;
        if (isUnconfirmed) {
          _errorMessage =
              'Your email address has not been confirmed yet. Please verify your email before logging in.';
        } else if (isInvalidCreds) {
          _errorMessage =
              'Invalid email or password. Please verify your credentials and try again.';
        } else if (isRateLimit) {
          _errorMessage =
              'Too many login attempts. Please wait a moment before trying again.';
        } else if (isNetwork) {
          _errorMessage =
              'Network connection error. Please check your internet connection or Wi-Fi and try again.';
        } else {
          _errorMessage = msg.isNotEmpty
              ? msg
              : 'Authentication failed. Please verify your credentials and try again.';
        }
      });
    } catch (e) {
      final str = e.toString().replaceAll('Exception:', '').trim();
      final strLower = str.toLowerCase();

      final isUnconfirmed = strLower.contains('email not confirmed') ||
          strLower.contains('email_not_confirmed');
      final isInvalidCreds = strLower.contains('invalid credentials') ||
          strLower.contains('invalid login credentials') ||
          strLower.contains('invalid_credentials');
      final isRateLimit = strLower.contains('429') ||
          strLower.contains('over_email_send_rate_limit') ||
          strLower.contains('rate limit');
      final isNetwork = strLower.contains('socket') ||
          strLower.contains('clientexception') ||
          strLower.contains('failed host lookup') ||
          strLower.contains('timeoutexception') ||
          strLower.contains('connection refused') ||
          strLower.contains('no internet') ||
          strLower.contains('network');

      setState(() {
        _isEmailUnconfirmed = isUnconfirmed;
        if (isUnconfirmed) {
          _errorMessage =
              'Your email address has not been confirmed yet. Please verify your email before logging in.';
        } else if (isInvalidCreds) {
          _errorMessage =
              'Invalid email or password. Please verify your credentials and try again.';
        } else if (isRateLimit) {
          _errorMessage =
              'Too many login attempts. Please wait a moment before trying again.';
        } else if (isNetwork) {
          _errorMessage =
              'Network connection error. Please check your internet connection or Wi-Fi and try again.';
        } else {
          _errorMessage = str;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (_isLoading || _isGoogleLoading) return;

    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
      _isEmailUnconfirmed = false;
    });

    try {
      final supabase = ref.read(supabaseServiceProvider);

      if (!supabase.isConfigured) {
        throw Exception(
            'Authentication service is currently unavailable. Please check your network and configuration.');
      }

      final launched = await supabase.signInWithGoogle();
      if (!launched) {
        throw Exception(
            'Could not launch authentication browser. Please verify device browser settings.');
      }
    } on AuthException catch (e) {
      final msgLower = e.message.toLowerCase();
      final isNetwork = msgLower.contains('network') ||
          msgLower.contains('socket') ||
          msgLower.contains('timeout') ||
          msgLower.contains('connection');

      if (mounted) {
        setState(() {
          if (isNetwork) {
            _errorMessage =
                'Network connection error. Please check your internet connection or Wi-Fi and try again.';
          } else {
            _errorMessage = e.message.isNotEmpty
                ? e.message
                : 'Google authentication failed. Please try again.';
          }
          _isGoogleLoading = false;
        });
      }
    } catch (e) {
      final str = e.toString().replaceAll('Exception:', '').trim();
      final strLower = str.toLowerCase();
      final isNetwork = strLower.contains('socket') ||
          strLower.contains('clientexception') ||
          strLower.contains('failed host lookup') ||
          strLower.contains('connection refused') ||
          strLower.contains('network');

      if (mounted) {
        setState(() {
          if (isNetwork) {
            _errorMessage =
                'Network connection error. Please check your internet connection or Wi-Fi and try again.';
          } else {
            _errorMessage = str.isNotEmpty
                ? str
                : 'Could not complete Google authentication.';
          }
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _handleResendConfirmation() async {
    if (_isResendingEmail || _resendCooldownSeconds > 0) return;

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your registered email address.'),
        ),
      );
      return;
    }

    setState(() => _isResendingEmail = true);
    try {
      final supabase = ref.read(supabaseServiceProvider);
      await supabase.resendConfirmationEmail(email);
      _startResendCooldown(60);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verification email resent! Please check your inbox and spam folders.',
            ),
            backgroundColor: AppColors.primaryBlue,
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AuthException catch (e) {
      final isRateLimit = e.statusCode == '429' ||
          e.code == 'over_email_send_rate_limit' ||
          e.message.toLowerCase().contains('rate limit') ||
          e.message.toLowerCase().contains('over_email_send_rate_limit');

      if (isRateLimit) {
        _startResendCooldown(60);
      }

      final friendlyMsg = isRateLimit
          ? 'Email rate limit reached. Please wait 60 seconds before requesting another verification email.'
          : (e.message.isNotEmpty
              ? e.message
              : 'Could not resend verification email.');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMsg),
            backgroundColor: AppColors.emergencyRed,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      final str = e.toString().replaceAll('Exception:', '').trim();
      final isRateLimit = str.contains('429') ||
          str.contains('over_email_send_rate_limit') ||
          str.toLowerCase().contains('rate limit');

      if (isRateLimit) {
        _startResendCooldown(60);
      }

      final friendlyMsg = isRateLimit
          ? 'Email rate limit reached. Please wait 60 seconds before requesting another verification email.'
          : 'Could not resend verification email: $str';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMsg),
            backgroundColor: AppColors.emergencyRed,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResendingEmail = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address to reset password.'),
        ),
      );
      return;
    }

    try {
      final supabase = ref.read(supabaseServiceProvider);
      await supabase.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset instructions sent to your email.'),
          ),
        );
      }
    } on AuthException catch (e) {
      final isRateLimit = e.statusCode == '429' ||
          e.code == 'over_email_send_rate_limit' ||
          e.message.toLowerCase().contains('rate limit');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRateLimit
                  ? 'Password reset rate limit reached. Please wait a moment before requesting another reset.'
                  : (e.message.isNotEmpty
                      ? e.message
                      : 'Could not send reset instructions.'),
            ),
            backgroundColor: AppColors.emergencyRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      final str = e.toString().replaceAll('Exception:', '').trim();
      final isRateLimit = str.contains('429') ||
          str.contains('over_email_send_rate_limit') ||
          str.toLowerCase().contains('rate limit');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRateLimit
                  ? 'Password reset rate limit reached. Please wait a moment before requesting another reset.'
                  : 'Could not send reset: $str',
            ),
            backgroundColor: AppColors.emergencyRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryText),
            onPressed: _handleBack,
          ),
          actions: [
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.guestSos),
              icon: const Icon(Icons.emergency_rounded,
                  size: 16, color: AppColors.emergencyRed),
              label: const Text(
                'Guest SOS',
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: SorynthLogo(size: 64, showText: false),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: primaryText,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to sync emergency contacts, profiles & team coordination.',
                    style: TextStyle(
                      fontSize: 14,
                      color: secondaryText,
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.emergencyRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.emergencyRed.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: AppColors.emergencyRed, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppColors.emergencyRed,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_isEmailUnconfirmed) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: (_isResendingEmail || _resendCooldownSeconds > 0)
                                    ? null
                                    : _handleResendConfirmation,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  disabledForegroundColor:
                                      AppColors.secondaryText,
                                  side: BorderSide(
                                    color: (_isResendingEmail || _resendCooldownSeconds > 0)
                                        ? AppColors.secondaryText
                                            .withValues(alpha: 0.3)
                                        : AppColors.primaryBlue,
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                icon: _isResendingEmail
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            AppColors.primaryBlue,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        _resendCooldownSeconds > 0
                                            ? Icons.hourglass_top_rounded
                                            : Icons.mark_email_read_outlined,
                                        size: 18,
                                        color: (_isResendingEmail ||
                                                _resendCooldownSeconds > 0)
                                            ? AppColors.secondaryText
                                            : AppColors.primaryBlue,
                                      ),
                                label: Text(
                                  _isResendingEmail
                                      ? 'Resending...'
                                      : (_resendCooldownSeconds > 0
                                          ? 'Resend in ${_resendCooldownSeconds}s'
                                          : 'Resend Verification Email'),
                                  style: TextStyle(
                                    color: (_isResendingEmail ||
                                            _resendCooldownSeconds > 0)
                                        ? AppColors.secondaryText
                                        : AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: TextButton.icon(
                                onPressed: () {
                                  context.push(
                                    AppRoutes.emailVerification,
                                    extra: _emailController.text.trim(),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(
                                  Icons.info_outline_rounded,
                                  size: 15,
                                  color: AppColors.primaryBlue,
                                ),
                                label: const Text(
                                  'View email verification steps',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                const SizedBox(height: 28),

                // Email field
                Text(
                  'Email Address',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  style: TextStyle(color: primaryText),
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Enter Email Address',
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppColors.secondaryText),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Password field
                Text(
                  'Password',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  style: TextStyle(color: primaryText),
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: '••••••••••••',
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.secondaryText),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.secondaryText,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    if (value.length < 6) {
                      return 'Must be at least 6 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _handleForgotPassword,
                    child: const Text('Forgot Password?'),
                  ),
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: (_isLoading || _isGoogleLoading) ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.white,
                            ),
                          ),
                        )
                      : const Text('Sign In'),
                ),

                const SizedBox(height: 20),

                // Alternative Authentication Options
                Row(
                  children: [
                    Expanded(
                      child: Divider(color: cardBorder, thickness: 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: secondaryText,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(color: cardBorder, thickness: 1),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Continue with Google Button
                OutlinedButton(
                  onPressed: (_isLoading || _isGoogleLoading)
                      ? null
                      : _handleGoogleLogin,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: cardBg,
                    foregroundColor: primaryText,
                    disabledForegroundColor: secondaryText,
                    side: BorderSide(
                      color: cardBorder,
                      width: 1.2,
                    ),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isGoogleLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primaryBlue,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const GoogleLogo(size: 20),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Continue with Google',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: primaryText,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.register),
                    child: RichText(
                      text: TextSpan(
                        text: "Don't have an account? ",
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 14,
                        ),
                        children: const [
                          TextSpan(
                            text: 'Create Account',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
}

