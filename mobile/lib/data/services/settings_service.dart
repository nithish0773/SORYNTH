import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/app_providers.dart';

/// Settings model holding user preferences across notifications,
/// emergency hardware, theme mode, and app localization.
class SorynthSettings {
  // Notifications
  final bool pushNotificationsEnabled;
  final bool sosStatusNotificationsEnabled;
  final bool rescueTeamUpdateNotificationsEnabled;
  final bool notificationSoundEnabled;
  final bool vibrationEnabled;

  // Emergency & Hardware
  final bool autoLoRaFallbackEnabled;
  final bool highAccuracyGpsPreferred;
  final bool meshRelayParticipate;

  // Preferences
  final ThemeMode themeMode;
  final String languageCode;

  const SorynthSettings({
    this.pushNotificationsEnabled = true,
    this.sosStatusNotificationsEnabled = true,
    this.rescueTeamUpdateNotificationsEnabled = true,
    this.notificationSoundEnabled = true,
    this.vibrationEnabled = true,
    this.autoLoRaFallbackEnabled = true,
    this.highAccuracyGpsPreferred = true,
    this.meshRelayParticipate = true,
    this.themeMode = ThemeMode.system,
    this.languageCode = 'en',
  });

  SorynthSettings copyWith({
    bool? pushNotificationsEnabled,
    bool? sosStatusNotificationsEnabled,
    bool? rescueTeamUpdateNotificationsEnabled,
    bool? notificationSoundEnabled,
    bool? vibrationEnabled,
    bool? autoLoRaFallbackEnabled,
    bool? highAccuracyGpsPreferred,
    bool? meshRelayParticipate,
    ThemeMode? themeMode,
    String? languageCode,
  }) {
    return SorynthSettings(
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      sosStatusNotificationsEnabled:
          sosStatusNotificationsEnabled ?? this.sosStatusNotificationsEnabled,
      rescueTeamUpdateNotificationsEnabled:
          rescueTeamUpdateNotificationsEnabled ??
              this.rescueTeamUpdateNotificationsEnabled,
      notificationSoundEnabled:
          notificationSoundEnabled ?? this.notificationSoundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      autoLoRaFallbackEnabled:
          autoLoRaFallbackEnabled ?? this.autoLoRaFallbackEnabled,
      highAccuracyGpsPreferred:
          highAccuracyGpsPreferred ?? this.highAccuracyGpsPreferred,
      meshRelayParticipate:
          meshRelayParticipate ?? this.meshRelayParticipate,
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}

/// Service managing persistent key-value configuration in SharedPreferences.
class SettingsService {
  final SharedPreferences _prefs;

  static const String _keyPush = 'sorynth_set_push_enabled';
  static const String _keySosNotif = 'sorynth_set_sos_notif_enabled';
  static const String _keyRescueNotif = 'sorynth_set_rescue_notif_enabled';
  static const String _keySound = 'sorynth_set_sound_enabled';
  static const String _keyVibration = 'sorynth_set_vibration_enabled';
  static const String _keyAutoLoRa = 'sorynth_set_auto_lora_fallback';
  static const String _keyHighGps = 'sorynth_set_high_gps';
  static const String _keyMesh = 'sorynth_set_mesh_participate';
  static const String _keyTheme = 'sorynth_set_theme_mode';
  static const String _keyLang = 'sorynth_set_language_code';

  SettingsService(this._prefs);

  SorynthSettings loadSettings() {
    final themeStr = _prefs.getString(_keyTheme) ?? 'system';
    final ThemeMode mode;
    switch (themeStr) {
      case 'light':
        mode = ThemeMode.light;
        break;
      case 'dark':
        mode = ThemeMode.dark;
        break;
      default:
        mode = ThemeMode.system;
    }

    return SorynthSettings(
      pushNotificationsEnabled: _prefs.getBool(_keyPush) ?? true,
      sosStatusNotificationsEnabled: _prefs.getBool(_keySosNotif) ?? true,
      rescueTeamUpdateNotificationsEnabled: _prefs.getBool(_keyRescueNotif) ?? true,
      notificationSoundEnabled: _prefs.getBool(_keySound) ?? true,
      vibrationEnabled: _prefs.getBool(_keyVibration) ?? true,
      autoLoRaFallbackEnabled: _prefs.getBool(_keyAutoLoRa) ?? true,
      highAccuracyGpsPreferred: _prefs.getBool(_keyHighGps) ?? true,
      meshRelayParticipate: _prefs.getBool(_keyMesh) ?? true,
      themeMode: mode,
      languageCode: _prefs.getString(_keyLang) ?? 'en',
    );
  }

  Future<void> saveSettings(SorynthSettings settings) async {
    await _prefs.setBool(_keyPush, settings.pushNotificationsEnabled);
    await _prefs.setBool(_keySosNotif, settings.sosStatusNotificationsEnabled);
    await _prefs.setBool(_keyRescueNotif, settings.rescueTeamUpdateNotificationsEnabled);
    await _prefs.setBool(_keySound, settings.notificationSoundEnabled);
    await _prefs.setBool(_keyVibration, settings.vibrationEnabled);
    await _prefs.setBool(_keyAutoLoRa, settings.autoLoRaFallbackEnabled);
    await _prefs.setBool(_keyHighGps, settings.highAccuracyGpsPreferred);
    await _prefs.setBool(_keyMesh, settings.meshRelayParticipate);

    final themeStr = settings.themeMode == ThemeMode.light
        ? 'light'
        : (settings.themeMode == ThemeMode.dark ? 'dark' : 'system');
    await _prefs.setString(_keyTheme, themeStr);
    await _prefs.setString(_keyLang, settings.languageCode);
  }
}

/// StateNotifier broadcasting and mutating settings dynamically.
class SettingsNotifier extends StateNotifier<SorynthSettings> {
  final SettingsService _service;

  SettingsNotifier(this._service) : super(_service.loadSettings());

  Future<void> updatePushNotifications(bool enabled) async {
    state = state.copyWith(pushNotificationsEnabled: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateSosStatusNotifications(bool enabled) async {
    state = state.copyWith(sosStatusNotificationsEnabled: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateRescueTeamNotifications(bool enabled) async {
    state = state.copyWith(rescueTeamUpdateNotificationsEnabled: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateNotificationSound(bool enabled) async {
    state = state.copyWith(notificationSoundEnabled: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateVibration(bool enabled) async {
    state = state.copyWith(vibrationEnabled: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateAutoLoRaFallback(bool enabled) async {
    state = state.copyWith(autoLoRaFallbackEnabled: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateHighAccuracyGps(bool enabled) async {
    state = state.copyWith(highAccuracyGpsPreferred: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateMeshRelayParticipate(bool enabled) async {
    state = state.copyWith(meshRelayParticipate: enabled);
    await _service.saveSettings(state);
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _service.saveSettings(state);
  }

  Future<void> updateLanguage(String code) async {
    state = state.copyWith(languageCode: code);
    await _service.saveSettings(state);
  }
}

/// Riverpod Providers
final settingsServiceProvider = Provider<SettingsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsService(prefs);
});

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SorynthSettings>((ref) {
  final service = ref.watch(settingsServiceProvider);
  return SettingsNotifier(service);
});
