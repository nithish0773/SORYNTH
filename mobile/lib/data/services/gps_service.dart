import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsQuality {
  unavailable,
  approximate, // Accuracy > 30 meters (e.g. cellular tower triangulation)
  accurate,    // Accuracy <= 30 meters (direct GNSS/GPS satellite fix)
}

class GpsResult {
  final bool isSuccess;
  final double latitude;
  final double longitude;
  final double accuracy; // Accuracy in meters reported by Android GPS HAL
  final double altitude;
  final DateTime timestamp; // Original GPS fix timestamp
  final bool isMocked;
  final String? errorMessage;
  final bool isPermissionDenied;
  final bool isServiceDisabled;

  const GpsResult({
    required this.isSuccess,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.accuracy = 0.0,
    this.altitude = 0.0,
    required this.timestamp,
    this.isMocked = false,
    this.errorMessage,
    this.isPermissionDenied = false,
    this.isServiceDisabled = false,
  });

  GpsQuality get quality {
    if (!isSuccess) return GpsQuality.unavailable;
    if (accuracy <= 30.0) return GpsQuality.accurate;
    return GpsQuality.approximate;
  }

  bool get isAccurate => quality == GpsQuality.accurate;
  bool get isApproximate => quality == GpsQuality.approximate;

  String get qualityBadgeLabel {
    switch (quality) {
      case GpsQuality.accurate:
        return 'Precise GPS Fix (±${accuracy.round()}m)';
      case GpsQuality.approximate:
        return 'Approximate Fix (±${accuracy.round()}m)';
      case GpsQuality.unavailable:
        return 'GPS Fix Unavailable';
    }
  }

  String? get warningMessage {
    if (quality == GpsQuality.approximate) {
      return 'GPS accuracy is ±${accuracy.round()}m. High-precision satellite lock pending; rescue perimeter will be expanded.';
    }
    return null;
  }

  factory GpsResult.success(Position pos) {
    return GpsResult(
      isSuccess: true,
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      timestamp: pos.timestamp,
      isMocked: pos.isMocked,
    );
  }

  factory GpsResult.failure({
    required String message,
    bool isPermissionDenied = false,
    bool isServiceDisabled = false,
  }) {
    return GpsResult(
      isSuccess: false,
      timestamp: DateTime.now(),
      errorMessage: message,
      isPermissionDenied: isPermissionDenied,
      isServiceDisabled: isServiceDisabled,
    );
  }
}

class GpsService {
  GpsService();

  /// Check GPS permissions and location services, then request accurate position
  Future<GpsResult> getCurrentLocation({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      // 1. Check if location services are enabled on the phone
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return GpsResult.failure(
          message: 'Location services (GPS) are turned off on your device.',
          isServiceDisabled: true,
        );
      }

      // 2. Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return GpsResult.failure(
            message: 'Location permission was denied. SORYNTH requires GPS for rescue operations.',
            isPermissionDenied: true,
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return GpsResult.failure(
          message: 'Location permission is permanently denied. Please enable it in device settings.',
          isPermissionDenied: true,
        );
      }

      // 3. Acquire current location with high accuracy directly from GNSS / GPS hardware
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 1),
        ),
      );

      return GpsResult.success(position);
    } catch (e) {
      debugPrint('[GpsService] Error acquiring high-accuracy GPS: $e. Checking last known...');
      // 4. Fallback to last known position if available
      try {
        final Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return GpsResult.success(lastKnown);
        }
      } catch (_) {}

      return GpsResult.failure(
        message: 'Could not obtain GPS fix. Please ensure you have an open view of the sky.',
      );
    }
  }

  /// Listen to live location updates
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }

  /// Open device location settings
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Open app permission settings
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
