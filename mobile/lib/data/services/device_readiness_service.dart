import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/providers/app_providers.dart';
import 'connectivity_service.dart';

enum ServiceReadinessStatus {
  ready,
  attentionRequired,
  permissionRequired,
  disabled,
  notAvailable,
}

class ServiceReadiness {
  final ServiceReadinessStatus status;
  final String title;
  final String description;
  final String actionLabel;
  final IconData icon;

  const ServiceReadiness({
    required this.status,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.icon,
  });

  bool get isReady => status == ServiceReadinessStatus.ready;
  bool get isPermissionRequired =>
      status == ServiceReadinessStatus.permissionRequired;
  bool get isDisabled => status == ServiceReadinessStatus.disabled;
}

class DeviceReadinessState {
  final ServiceReadiness bluetooth;
  final ServiceReadiness location;
  final ServiceReadiness internet;
  final bool isChecking;

  const DeviceReadinessState({
    required this.bluetooth,
    required this.location,
    required this.internet,
    this.isChecking = false,
  });

  bool get isAllReady =>
      bluetooth.isReady && location.isReady && internet.isReady;

  bool get hasIssues => !isAllReady;
}

/// Service that checks actual device hardware and permissions.
class DeviceReadinessService {
  final ConnectivityService _connectivity;

  DeviceReadinessService({required ConnectivityService connectivity})
      : _connectivity = connectivity;

  /// Inspect Bluetooth adapter & Android BLE permissions
  Future<ServiceReadiness> checkBluetooth() async {
    try {
      if (kIsWeb) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.notAvailable,
          title: 'Bluetooth Not Available',
          description: 'Web platform does not support native BLE transceiver communication.',
          actionLabel: 'Unsupported',
          icon: Icons.bluetooth_disabled_rounded,
        );
      }

      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.notAvailable,
          title: 'Bluetooth Hardware Missing',
          description: 'This device does not have BLE hardware required for ESP32 mesh relay.',
          actionLabel: 'Unsupported',
          icon: Icons.bluetooth_disabled_rounded,
        );
      }

      // Check Bluetooth permissions (Android 12+ requires SCAN & CONNECT)
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;

      if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.permissionRequired,
          title: 'Bluetooth Permission Blocked',
          description: 'Nearby device permission was permanently denied in Android. Please enable it in App Settings.',
          actionLabel: 'Open App Settings',
          icon: Icons.bluetooth_searching_rounded,
        );
      }

      if (!scanStatus.isGranted || !connectStatus.isGranted) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.permissionRequired,
          title: 'Bluetooth Permission Required',
          description: 'SORYNTH needs nearby device permission to discover and pair with your ESP32 LoRa node.',
          actionLabel: 'Grant Permission',
          icon: Icons.bluetooth_searching_rounded,
        );
      }

      // Check Adapter State
      final adapter = await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => BluetoothAdapterState.unknown);

      if (adapter != BluetoothAdapterState.on) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.disabled,
          title: 'Bluetooth is Disabled',
          description: 'Turn ON Bluetooth to communicate with remote ESP32 LoRa mesh transceivers.',
          actionLabel: 'Turn ON Bluetooth',
          icon: Icons.bluetooth_disabled_rounded,
        );
      }

      return const ServiceReadiness(
        status: ServiceReadinessStatus.ready,
        title: 'Bluetooth BLE Mesh Ready',
        description: 'Hardware driver is active and ready to pair with SORYNTH ESP32 radio nodes.',
        actionLabel: 'Ready',
        icon: Icons.bluetooth_connected_rounded,
      );
    } catch (e) {
      debugPrint('[DeviceReadinessService] Bluetooth check exception: $e');
      return const ServiceReadiness(
        status: ServiceReadinessStatus.attentionRequired,
        title: 'Bluetooth Check Inconclusive',
        description: 'Could not query Bluetooth adapter. Offline relay may be limited.',
        actionLabel: 'Recheck',
        icon: Icons.bluetooth_rounded,
      );
    }
  }

  /// Inspect Location permissions & GPS hardware service
  Future<ServiceReadiness> checkLocation() async {
    try {
      final perm = await Geolocator.checkPermission();

      if (perm == LocationPermission.deniedForever) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.permissionRequired,
          title: 'Location Permission Blocked',
          description: 'Location access is permanently blocked. Precise GPS coordinates cannot be attached.',
          actionLabel: 'Open App Settings',
          icon: Icons.location_off_rounded,
        );
      }

      if (perm == LocationPermission.denied) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.permissionRequired,
          title: 'Location Permission Needed',
          description: 'GPS coordinates are critical so rescue teams know your exact disaster location.',
          actionLabel: 'Grant Permission',
          icon: Icons.location_searching_rounded,
        );
      }

      final isGpsOn = await Geolocator.isLocationServiceEnabled();
      if (!isGpsOn) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.disabled,
          title: 'GPS / Location Service OFF',
          description: 'Device location is turned off in Android settings. Turn ON GPS for emergency dispatch.',
          actionLabel: 'Enable GPS',
          icon: Icons.location_off_rounded,
        );
      }

      return const ServiceReadiness(
        status: ServiceReadinessStatus.ready,
        title: 'GPS & Location Ready',
        description: 'High-accuracy satellite coordinates will be embedded in your emergency alerts.',
        actionLabel: 'Ready',
        icon: Icons.my_location_rounded,
      );
    } catch (e) {
      debugPrint('[DeviceReadinessService] Location check exception: $e');
      return const ServiceReadiness(
        status: ServiceReadinessStatus.attentionRequired,
        title: 'Location Check Inconclusive',
        description: 'Could not query device location services.',
        actionLabel: 'Recheck',
        icon: Icons.location_searching_rounded,
      );
    }
  }

  /// Inspect internet reachability (Wi-Fi or Mobile Data)
  Future<ServiceReadiness> checkInternet() async {
    try {
      final isOnline = await _connectivity.checkActualInternetReachability();
      if (isOnline) {
        return const ServiceReadiness(
          status: ServiceReadinessStatus.ready,
          title: 'Internet Cloud Uplink Active',
          description: 'Connected via Wi-Fi or Mobile Data. Direct synchronization with Rescue Dashboard is ready.',
          actionLabel: 'Ready',
          icon: Icons.cloud_done_rounded,
        );
      }

      return const ServiceReadiness(
        status: ServiceReadinessStatus.attentionRequired,
        title: 'Offline Mode Active',
        description: 'No active internet connection. SORYNTH will automatically queue alerts locally and relay via ESP32 LoRa radio.',
        actionLabel: 'Check Network',
        icon: Icons.cloud_off_rounded,
      );
    } catch (e) {
      debugPrint('[DeviceReadinessService] Internet check exception: $e');
      return const ServiceReadiness(
        status: ServiceReadinessStatus.attentionRequired,
        title: 'Offline Mode Active',
        description: 'Operating in offline emergency mode. LoRa radio relay and local persistence are active.',
        actionLabel: 'Check Network',
        icon: Icons.cloud_off_rounded,
      );
    }
  }

  /// Check all 3 services concurrently
  Future<DeviceReadinessState> checkAll() async {
    final results = await Future.wait([
      checkBluetooth(),
      checkLocation(),
      checkInternet(),
    ]);

    return DeviceReadinessState(
      bluetooth: results[0],
      location: results[1],
      internet: results[2],
      isChecking: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------

  Future<void> requestBluetoothPermission() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  Future<void> enableBluetooth() async {
    try {
      // FlutterBluePlus turnOn works on Android with user prompt
      await FlutterBluePlus.turnOn();
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<void> requestLocationPermission() async {
    await Geolocator.requestPermission();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}

/// Riverpod Providers
final deviceReadinessServiceProvider = Provider<DeviceReadinessService>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return DeviceReadinessService(connectivity: connectivity);
});

final deviceReadinessNotifierProvider =
    StateNotifierProvider<DeviceReadinessNotifier, DeviceReadinessState>((ref) {
  final service = ref.watch(deviceReadinessServiceProvider);
  return DeviceReadinessNotifier(service);
});

class DeviceReadinessNotifier extends StateNotifier<DeviceReadinessState> {
  final DeviceReadinessService _service;

  DeviceReadinessNotifier(this._service)
      : super(const DeviceReadinessState(
          bluetooth: ServiceReadiness(
            status: ServiceReadinessStatus.ready,
            title: 'Checking Bluetooth...',
            description: '',
            actionLabel: 'Checking',
            icon: Icons.bluetooth_rounded,
          ),
          location: ServiceReadiness(
            status: ServiceReadinessStatus.ready,
            title: 'Checking Location...',
            description: '',
            actionLabel: 'Checking',
            icon: Icons.location_searching_rounded,
          ),
          internet: ServiceReadiness(
            status: ServiceReadinessStatus.ready,
            title: 'Checking Internet...',
            description: '',
            actionLabel: 'Checking',
            icon: Icons.cloud_queue_rounded,
          ),
          isChecking: true,
        )) {
    refresh();
  }

  Future<void> refresh() async {
    state = DeviceReadinessState(
      bluetooth: state.bluetooth,
      location: state.location,
      internet: state.internet,
      isChecking: true,
    );
    final newState = await _service.checkAll();
    state = newState;
  }
}
