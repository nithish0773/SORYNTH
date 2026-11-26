import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../../core/constants/app_constants.dart';
import '../models/emergency_model.dart';

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  transmitting,
  failed,
}

class BleTelemetry {
  final BleConnectionStatus status;
  final String? deviceName;
  final String? deviceId;
  final int rssi; // Signal strength dBm
  final int currentHops;
  final bool isSimulated;
  final String? lastMessage;

  const BleTelemetry({
    required this.status,
    this.deviceName,
    this.deviceId,
    this.rssi = -100,
    this.currentHops = 0,
    required this.isSimulated,
    this.lastMessage,
  });

  BleTelemetry copyWith({
    BleConnectionStatus? status,
    String? deviceName,
    String? deviceId,
    int? rssi,
    int? currentHops,
    bool? isSimulated,
    String? lastMessage,
  }) {
    return BleTelemetry(
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      deviceId: deviceId ?? this.deviceId,
      rssi: rssi ?? this.rssi,
      currentHops: currentHops ?? this.currentHops,
      isSimulated: isSimulated ?? this.isSimulated,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

class BleTransmissionResult {
  final bool isSuccess;
  final String emergencyId;
  final EmergencyStatus finalStatus;
  final int hopCount;
  final List<String> relayNodes;
  final bool isSimulated;
  final String message;
  final int? rssi;

  const BleTransmissionResult({
    required this.isSuccess,
    required this.emergencyId,
    required this.finalStatus,
    this.hopCount = 0,
    this.relayNodes = const [],
    required this.isSimulated,
    required this.message,
    this.rssi,
  });
}

abstract class BluetoothService {
  BleTelemetry get currentTelemetry;
  Stream<BleTelemetry> get telemetryStream;
  bool get isSimulated;
  String get modeLabel;

  Future<bool> isBluetoothSupportedAndEnabled();
  Future<void> startScan({Duration timeout = const Duration(seconds: 6)});
  Future<void> stopScan();
  Future<bool> connectToNode(String deviceId);
  Future<void> disconnect();

  /// Send emergency message over BLE to ESP32 transceiver
  Future<BleTransmissionResult> transmitEmergencyPacket(
    EmergencyModel emergency, {
    void Function(String progressStep)? onProgress,
  });

  void dispose();
}

/// ============================================================================
/// REAL HARDWARE MODE: PRODUCTION FLUTTER_BLUE_PLUS HARDWARE BLE SERVICE
/// Designed for physical ESP32 + LoRa hardware transceivers.
/// Strictly enforces the rule: NO FAKE SUCCESS. If no physical ESP32 is
/// connected, it returns QUEUED_LOCALLY and never claims delivery!
/// ============================================================================
class FlutterBluePlusBluetoothService implements BluetoothService {
  final _telemetryController = StreamController<BleTelemetry>.broadcast();
  BleTelemetry _telemetry = const BleTelemetry(
    status: BleConnectionStatus.disconnected,
    isSimulated: false,
    lastMessage: 'Hardware BLE Driver Initialized (Awaiting Physical Device)',
  );

  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _txCharacteristic;
  fbp.BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription? _scanSubscription;

  @override
  bool get isSimulated => false;

  @override
  String get modeLabel => 'REAL HARDWARE MODE';

  @override
  BleTelemetry get currentTelemetry => _telemetry;

  @override
  Stream<BleTelemetry> get telemetryStream => _telemetryController.stream;

  void _updateTelemetry(BleTelemetry updated) {
    _telemetry = updated;
    _telemetryController.add(_telemetry);
  }

  @override
  Future<bool> isBluetoothSupportedAndEnabled() async {
    try {
      final isSupported = await fbp.FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      final adapterState = await fbp.FlutterBluePlus.adapterState.first;
      return adapterState == fbp.BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('[HardwareBLE] Error checking adapter state: $e');
      return false;
    }
  }

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    _updateTelemetry(_telemetry.copyWith(status: BleConnectionStatus.scanning));
    try {
      await fbp.FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: [fbp.Guid(AppConstants.esp32ServiceUuid)],
      );

      _scanSubscription?.cancel();
      _scanSubscription = fbp.FlutterBluePlus.scanResults.listen((results) {
        for (fbp.ScanResult r in results) {
          if (r.device.platformName.toUpperCase().contains(AppConstants.esp32DevicePrefix)) {
            connectToNode(r.device.remoteId.str);
            break;
          }
        }
      });
    } catch (e) {
      debugPrint('[HardwareBLE] Scan error: $e');
      _updateTelemetry(_telemetry.copyWith(status: BleConnectionStatus.failed, lastMessage: e.toString()));
    }
  }

  @override
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  @override
  Future<bool> connectToNode(String deviceId) async {
    try {
      _updateTelemetry(_telemetry.copyWith(status: BleConnectionStatus.connecting));
      final device = fbp.BluetoothDevice.fromId(deviceId);
      await device.connect(timeout: const Duration(seconds: 8));
      _connectedDevice = device;

      // Discover GATT Services
      final services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().toUpperCase() == AppConstants.esp32ServiceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toUpperCase() == AppConstants.esp32TxCharUuid) {
              _txCharacteristic = c;
            } else if (c.uuid.toString().toUpperCase() == AppConstants.esp32RxCharUuid) {
              _rxCharacteristic = c;
              await c.setNotifyValue(true);
            }
          }
        }
      }

      final rssi = await device.readRssi();
      _updateTelemetry(
        _telemetry.copyWith(
          status: BleConnectionStatus.connected,
          deviceName: device.platformName.isNotEmpty ? device.platformName : 'ESP32 LoRa Node',
          deviceId: device.remoteId.str,
          rssi: rssi,
          lastMessage: 'Connected to Physical SORYNTH ESP32 Node',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[HardwareBLE] Connection error: $e');
      _updateTelemetry(_telemetry.copyWith(status: BleConnectionStatus.failed, lastMessage: e.toString()));
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
      _connectedDevice = null;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _updateTelemetry(
        _telemetry.copyWith(
          status: BleConnectionStatus.disconnected,
          lastMessage: 'Disconnected from physical ESP32',
        ),
      );
    } catch (e) {
      debugPrint('[HardwareBLE] Disconnect error: $e');
    }
  }

  @override
  Future<BleTransmissionResult> transmitEmergencyPacket(
    EmergencyModel emergency, {
    void Function(String progressStep)? onProgress,
  }) async {
    // If physical hardware is not connected, report accurately without inventing success!
    if (_txCharacteristic == null || _connectedDevice == null) {
      return BleTransmissionResult(
        isSuccess: false,
        emergencyId: emergency.emergencyId,
        finalStatus: EmergencyStatus.queuedLocally,
        isSimulated: false,
        message: 'No physical ESP32 transceiver connected. Alert saved in offline queue (PENDING HARDWARE TRANSMISSION).',
      );
    }

    try {
      onProgress?.call('Writing 32-byte payload to physical ESP32 GATT TX characteristic...');
      final payloadBytes = utf8.encode(jsonEncode(emergency.toLoRaPayload()));
      await _txCharacteristic!.write(payloadBytes, withoutResponse: false);

      onProgress?.call('Packet delivered to ESP32 buffer. LoRa radio transmitting over 868MHz...');
      final completer = Completer<BleTransmissionResult>();

      final sub = _rxCharacteristic?.onValueReceived.listen((value) {
        try {
          final ackStr = utf8.decode(value);
          final ackJson = jsonDecode(ackStr);
          completer.complete(
            BleTransmissionResult(
              isSuccess: true,
              emergencyId: emergency.emergencyId,
              finalStatus: EmergencyStatus.gatewayReceived,
              hopCount: ackJson['hop_count'] ?? 1,
              relayNodes: [ackJson['node_id'] ?? 'ESP32_RELAY'],
              isSimulated: false,
              message: 'Verified LoRa ACK received from physical ESP32 gateway.',
            ),
          );
        } catch (_) {}
      });

      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          sub?.cancel();
          return BleTransmissionResult(
            isSuccess: false,
            emergencyId: emergency.emergencyId,
            finalStatus: EmergencyStatus.transmittingViaLora,
            isSimulated: false,
            message: 'Awaiting LoRa mesh ACK. Packet stored in ESP32 radio buffer for repeated broadcast.',
          );
        },
      );
    } catch (e) {
      return BleTransmissionResult(
        isSuccess: false,
        emergencyId: emergency.emergencyId,
        finalStatus: EmergencyStatus.failed,
        isSimulated: false,
        message: 'Physical BLE transmission error: $e',
      );
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _telemetryController.close();
  }
}
