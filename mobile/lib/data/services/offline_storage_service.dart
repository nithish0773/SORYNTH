import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../models/emergency_model.dart';

class OfflineStorageService {
  final SharedPreferences _prefs;

  OfflineStorageService(this._prefs);

  static Future<OfflineStorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return OfflineStorageService(prefs);
  }

  // ---------------------------------------------------------------------------
  // Onboarding & General App Settings
  // ---------------------------------------------------------------------------
  bool isOnboardingCompleted() {
    return _prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    await _prefs.setBool(AppConstants.keyOnboardingComplete, completed);
  }

  // ---------------------------------------------------------------------------
  // Guest Emergency Identity
  // ---------------------------------------------------------------------------
  String getOrCreateGuestId() {
    final existing = _prefs.getString(AppConstants.keyGuestId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    // Generate unpredictable cryptographically secure identifier
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    final hexString = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final newGuestId = 'GUEST-$hexString';
    _prefs.setString(AppConstants.keyGuestId, newGuestId);
    return newGuestId;
  }

  // ---------------------------------------------------------------------------
  // Active Emergency Session
  // ---------------------------------------------------------------------------
  String? getActiveEmergencyId() {
    return _prefs.getString(AppConstants.keyActiveEmergencyId);
  }

  Future<void> saveActiveEmergencyId(String emergencyId) async {
    await _prefs.setString(AppConstants.keyActiveEmergencyId, emergencyId);
  }

  Future<void> clearActiveEmergency() async {
    await _prefs.remove(AppConstants.keyActiveEmergencyId);
  }

  // ---------------------------------------------------------------------------
  // Offline SOS Emergency Queue & History Persistence
  // ---------------------------------------------------------------------------

  List<EmergencyModel> getAllEmergencies() {
    try {
      final rawList = _prefs.getStringList(AppConstants.keyPendingEmergencies);
      if (rawList == null || rawList.isEmpty) return [];

      return rawList.map((itemStr) {
        final Map<String, dynamic> map = jsonDecode(itemStr);
        return EmergencyModel.fromJson(map);
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('[OfflineStorage] Error reading emergencies: $e');
      return [];
    }
  }

  List<EmergencyModel> getPendingEmergencies() {
    return getAllEmergencies().where((e) {
      return e.status != EmergencyStatus.uploadedToServer &&
          e.status != EmergencyStatus.rescueTeamAcknowledged &&
          e.status != EmergencyStatus.inAction &&
          e.status != EmergencyStatus.resolved &&
          e.status != EmergencyStatus.cancelled;
    }).toList();
  }

  EmergencyModel? getEmergencyById(String emergencyId) {
    final list = getAllEmergencies();
    final index = list.indexWhere((e) => e.emergencyId == emergencyId);
    if (index != -1) return list[index];
    return null;
  }

  Future<void> saveEmergency(EmergencyModel emergency) async {
    final list = getAllEmergencies();
    final existingIndex =
        list.indexWhere((e) => e.emergencyId == emergency.emergencyId);

    if (existingIndex >= 0) {
      list[existingIndex] = emergency;
    } else {
      list.insert(0, emergency);
    }

    final rawList = list.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(AppConstants.keyPendingEmergencies, rawList);
    debugPrint('[OfflineStorage] Saved emergency: ${emergency.emergencyId} with status ${emergency.status.code}');
  }

  Future<void> updateEmergencyStatus(
    String emergencyId,
    EmergencyStatus newStatus, {
    int? hopCount,
    List<String>? relayPath,
    DateTime? acknowledgedAt,
    DateTime? resolvedAt,
  }) async {
    final existing = getEmergencyById(emergencyId);
    if (existing == null) return;

    final updated = existing.copyWith(
      status: newStatus,
      hopCount: hopCount ?? existing.hopCount,
      relayPath: relayPath ?? existing.relayPath,
      acknowledgedAt: acknowledgedAt ?? existing.acknowledgedAt,
      resolvedAt: resolvedAt ?? existing.resolvedAt,
    );

    await saveEmergency(updated);
  }

  Future<void> removeEmergency(String emergencyId) async {
    final list = getAllEmergencies();
    list.removeWhere((e) => e.emergencyId == emergencyId);
    final rawList = list.map((e) => jsonEncode(e.toJson())).toList();
    await _prefs.setStringList(AppConstants.keyPendingEmergencies, rawList);
  }
}

