import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routing/app_router.dart';
import '../../data/services/settings_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  PermissionStatus _notifPermission = PermissionStatus.granted;
  LocationPermission _locPermission = LocationPermission.always;
  bool _isGpsHardwareOn = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkHardwareAndPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkHardwareAndPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkHardwareAndPermissions() async {
    try {
      final notif = await Permission.notification.status;
      final loc = await Geolocator.checkPermission();
      final gpsOn = await Geolocator.isLocationServiceEnabled();

      if (mounted) {
        setState(() {
          _notifPermission = notif;
          _locPermission = loc;
          _isGpsHardwareOn = gpsOn;
        });
      }
    } catch (_) {
      // Ignored
    }
  }

  Future<void> _confirmDisableNotification({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.emergencyRed),
            SizedBox(width: 8),
            Text('Safety Warning'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Enabled'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergencyRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable Anyway'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      onConfirm();
    }
  }

  void _showHelpSupportDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Help & Emergency Support',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How does offline SOS work?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primaryTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                'When internet connectivity is unavailable, SORYNTH broadcasts a compact 32-byte emergency packet via Bluetooth Low Energy to a paired ESP32 node. The node transmits over LoRa radio mesh to neighboring stations until an internet gateway uploads it to rescue teams.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
              const SizedBox(height: 12),
              Text(
                'Can I use SORYNTH without an account?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primaryTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                'Yes. Guest SOS is permanently active and requires zero registration or credentials.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
              const SizedBox(height: 12),
              Text(
                'How do I maintain GPS accuracy?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primaryTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                'Keep device Location Services turned ON. SORYNTH attempts high-precision satellite acquisition before attaching coordinates to emergency broadcasts.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicyDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Privacy & Civilian Data Safety',
          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Zero Constant Tracking',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primaryTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                'SORYNTH does not track or log your location in the background. GPS coordinates are captured and broadcast solely when you intentionally trigger an emergency SOS alert.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
              const SizedBox(height: 12),
              Text(
                'Emergency Broadcast Data',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primaryTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                'Emergency alerts contain your emergency category, situational notes, contact details, timestamp, and coordinates. This data is delivered directly to official rescue centers via encrypted Supabase cloud endpoints or radio mesh packets.',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = theme.colorScheme.surface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.borderLight;
    final primaryTextColor = isDark ? AppColors.white : AppColors.textDark;
    final secondaryTextColor = isDark ? AppColors.darkSecondaryText : AppColors.secondaryText;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SECTION A: NOTIFICATIONS
              _buildSectionHeader('Notifications & Emergency Alerts', isDark),
              Material(
                color: cardBg,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: borderColor),
                ),
                child: Column(
                  children: [
                    if (!_notifPermission.isGranted) ...[
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warningYellow.withValues(alpha: isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.warningYellow.withValues(alpha: isDark ? 0.6 : 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_paused_rounded,
                                  color: AppColors.warningYellow, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Android notification permission is disabled. You may miss critical rescue updates.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: primaryTextColor,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => openAppSettings(),
                                child: const Text('Enable', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: borderColor),
                    ],

                    SwitchListTile.adaptive(
                      title: Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Allow notifications when app is backgrounded', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.pushNotificationsEnabled,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) => notifier.updatePushNotifications(val),
                    ),
                    Divider(height: 1, color: borderColor),

                    SwitchListTile.adaptive(
                      title: Text('SOS Status Alerts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Notify when your SOS is acknowledged or relayed', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.sosStatusNotificationsEnabled,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) {
                        if (!val) {
                          _confirmDisableNotification(
                            title: 'Disable SOS Status Notifications?',
                            message: 'Disabling SOS notifications may prevent you from seeing real-time confirmation when search & rescue teams receive your alert.',
                            onConfirm: () => notifier.updateSosStatusNotifications(false),
                          );
                        } else {
                          notifier.updateSosStatusNotifications(true);
                        }
                      },
                    ),
                    Divider(height: 1, color: borderColor),

                    SwitchListTile.adaptive(
                      title: Text('Rescue Team Updates', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Receive arrival ETA and rescue instructions', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.rescueTeamUpdateNotificationsEnabled,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) {
                        if (!val) {
                          _confirmDisableNotification(
                            title: 'Disable Rescue Team Updates?',
                            message: 'Disabling rescue team notifications means you will not receive immediate push alerts when teams update their dispatch status.',
                            onConfirm: () => notifier.updateRescueTeamNotifications(false),
                          );
                        } else {
                          notifier.updateRescueTeamNotifications(true);
                        }
                      },
                    ),
                    Divider(height: 1, color: borderColor),

                    SwitchListTile.adaptive(
                      title: Text('Sound Alerts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Play sound on incoming emergency events', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.notificationSoundEnabled,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) => notifier.updateNotificationSound(val),
                    ),
                    Divider(height: 1, color: borderColor),

                    SwitchListTile.adaptive(
                      title: Text('Vibration Feedback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Haptic feedback for hold actions and alerts', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.vibrationEnabled,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) => notifier.updateVibration(val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // SECTION B: EMERGENCY & LOCATION
              _buildSectionHeader('Emergency & Hardware Diagnostics', isDark),
              Material(
                color: cardBg,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: borderColor),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        _locPermission == LocationPermission.always ||
                                _locPermission == LocationPermission.whileInUse
                            ? Icons.location_on_rounded
                            : Icons.location_off_rounded,
                        color: _locPermission == LocationPermission.always ||
                                _locPermission == LocationPermission.whileInUse
                            ? AppColors.successGreen
                            : AppColors.warningYellow,
                      ),
                      title: Text('Location Permission', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text(
                        _locPermission.name.toUpperCase(),
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                      trailing: TextButton(
                        onPressed: () => openAppSettings(),
                        child: const Text('Manage', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    Divider(height: 1, color: borderColor),

                    ListTile(
                      leading: Icon(
                        _isGpsHardwareOn
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_off_rounded,
                        color: _isGpsHardwareOn
                            ? AppColors.successGreen
                            : AppColors.emergencyRed,
                      ),
                      title: Text('GPS Hardware Service', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text(
                        _isGpsHardwareOn ? 'ENABLED & READY' : 'DISABLED IN SYSTEM',
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                      trailing: !_isGpsHardwareOn
                          ? TextButton(
                              onPressed: () => Geolocator.openLocationSettings(),
                              child: const Text('Enable', style: TextStyle(fontSize: 12)),
                            )
                          : null,
                    ),
                    Divider(height: 1, color: borderColor),

                    SwitchListTile.adaptive(
                      title: Text('Auto-LoRa Radio Fallback', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Automatically transmit via ESP32 LoRa when offline', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.autoLoRaFallbackEnabled,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) => notifier.updateAutoLoRaFallback(val),
                    ),
                    Divider(height: 1, color: borderColor),

                    SwitchListTile.adaptive(
                      title: Text('High-Accuracy GPS Preferred', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Wait for high-accuracy satellite lock (<= 30m)', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      value: settings.highAccuracyGpsPreferred,
                      activeTrackColor: AppColors.primaryBlue,
                      onChanged: (val) => notifier.updateHighAccuracyGps(val),
                    ),
                    Divider(height: 1, color: borderColor),

                    ListTile(
                      leading: const Icon(Icons.health_and_safety_rounded, color: AppColors.primaryBlue),
                      title: Text('Run Full Pre-Flight Device Readiness', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Interactive Bluetooth, GPS & Internet status diagnostics', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: secondaryTextColor),
                      onTap: () => context.push(AppRoutes.deviceReadiness),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // SECTION C: APP PREFERENCES
              _buildSectionHeader('App Preferences & About', isDark),
              Material(
                color: cardBg,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: borderColor),
                ),
                child: Column(
                  children: [
                    // Theme Mode Selector
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Appearance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                          const SizedBox(height: 8),
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                label: Text('System', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.brightness_auto_rounded, size: 16),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                label: Text('Light', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.light_mode_rounded, size: 16),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text('Dark', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.dark_mode_rounded, size: 16),
                              ),
                            ],
                            selected: {settings.themeMode},
                            onSelectionChanged: (set) {
                              if (set.isNotEmpty) {
                                notifier.updateThemeMode(set.first);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: borderColor),

                    ListTile(
                      leading: const Icon(Icons.language_rounded, color: AppColors.primaryBlue),
                      title: Text('Language', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('English (International Rescue Standard)', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      trailing: const Icon(Icons.check_rounded, color: AppColors.successGreen, size: 18),
                    ),
                    Divider(height: 1, color: borderColor),

                    ListTile(
                      leading: const Icon(Icons.help_outline_rounded, color: AppColors.primaryBlue),
                      title: Text('Help & Emergency Support', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: secondaryTextColor),
                      onTap: _showHelpSupportDialog,
                    ),
                    Divider(height: 1, color: borderColor),

                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.primaryBlue),
                      title: Text('Privacy & Civilian Data Safety', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: secondaryTextColor),
                      onTap: _showPrivacyPolicyDialog,
                    ),
                    Divider(height: 1, color: borderColor),

                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, color: AppColors.primaryBlue),
                      title: Text('About SORYNTH', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryTextColor)),
                      subtitle: Text('Version 1.0.0+1 • Production Engine', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: secondaryTextColor),
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'SORYNTH',
                          applicationVersion: '1.0.0+1 (Production Build)',
                          applicationLegalese: 'Hybrid Internet and LoRa-Based Emergency SOS Communication System',
                          children: const [
                            SizedBox(height: 12),
                            Text(
                              'SORYNTH connects distressed citizens to rescue centers through online internet or ESP32-powered LoRa radio mesh relays without relying on cellular towers.',
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.darkSecondaryText : AppColors.secondaryText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
