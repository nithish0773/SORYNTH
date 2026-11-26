# SORYNTH - ESP32 & LoRa Hardware Communication Specification

## 1. System Overview

SORYNTH is a hybrid emergency communication system. When normal cellular data / Wi-Fi is unavailable, the SORYNTH mobile application connects to an external portable transceiver module via **Bluetooth Low Energy (BLE)**.

The external module consists of:
- **Microcontroller**: ESP32 (WROOM-32 or ESP32-S3)
- **Long Range Radio**: Semtech SX1276/SX1278 (433MHz / 868MHz / 915MHz) or SX1262 LoRa module
- **Antenna**: Tuned dipole/whip LoRa antenna
- **User Interface**: Tri-color RGB LED (Status indication) + Emergency Tactile Switch
- **Power**: 3.7V 18650/LiPo Battery with TP4056 charging IC & 3.3V LDO regulator.

```
+------------------+         BLE          +-----------------------+
|  SORYNTH Mobile  | <==================> |    ESP32 Transceiver  |
|   Application    |   (2.4GHz GATT)      | (LoRa Master / Node)  |
+------------------+                      +-----------------------+
                                                     |
                                                     | LoRa Radio (868/915/433 MHz)
                                                     v
                                          +-----------------------+
                                          |  Nearby LoRa Relays   |
                                          |   (Mesh Hop 1..N)     |
                                          +-----------------------+
                                                     |
                                                     | LoRa Radio
                                                     v
                                          +-----------------------+
                                          | LoRa Internet Gateway |
                                          |  (ESP32 + Wi-Fi/GSM)  |
                                          +-----------------------+
                                                     |
                                                     | HTTPS / Realtime
                                                     v
                                          +-----------------------+
                                          |  Supabase Cloud DB    |
                                          |  & Rescue Dashboard   |
                                          +-----------------------+
```

---

## 2. Bluetooth Low Energy (BLE) GATT Architecture

### 2.1 UUIDs
- **Primary Service UUID**: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` (Nordic UART Service standard)
- **SOS Transmission Characteristic (Write / WriteWithoutResponse)**: 
  `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (Mobile App -> ESP32)
- **ACK / Telemetry Characteristic (Notify / Read)**:
  `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (ESP32 -> Mobile App)

### 2.2 BLE Advertising
- **Device Local Name**: `SORYNTH-NODE-XXXX` (where `XXXX` is the last 4 characters of ESP32 MAC address).
- **Service Data**: Broadcasts battery level, LoRa channel state, and node ID in advertising packet.

---

## 3. LoRa Over-The-Air Packet Specifications

LoRa has restricted bandwidth and duty-cycle regulations (e.g. EU868 1% duty cycle, US915 FCC limits). Large JSON payloads must **not** be transmitted over LoRa.

### 3.1 Compact LoRa Binary Payload (Total: 32 Bytes)
```
Offset (Bytes) | Field Name       | Type             | Description
---------------+------------------+------------------+-------------------------------------
0..1           | Magic Header     | uint16 (0x5359)  | "SY" = SORYNTH Packet Identifier
2              | Packet Version   | uint8 (0x01)     | Protocol version 1
3..6           | Sequence / ID    | uint32           | Numeric SOS Identifier (e.g. 100001)
7              | Emergency Type   | uint8            | 1:MEDICAL, 2:ACCIDENT, 3:FIRE, 
               |                  |                  | 4:NATURAL_DISASTER, 5:LOST, 6:OTHER
8..11          | Latitude (x10^6) | int32            | Signed 32-bit fixed point integer
12..15         | Longitude (x10^6)| int32            | Signed 32-bit fixed point integer
16..17         | Accuracy (meters)| uint16           | GPS Accuracy in decimeters (0..6553m)
18             | Hop Count        | uint8            | Current hop count (0 initially)
19             | Max Hops (TTL)   | uint8            | Maximum allowable hops (default: 5)
20..23         | Node Origin ID   | uint32           | Originating ESP32 Node ID
24..27         | Timestamp (Unix) | uint32           | Seconds since epoch
28..29         | Status & Flags   | uint16           | Bitfield: is_guest(1), ack_req(1)...
30..31         | CRC16 Checksum   | uint16 (CCITT)   | Integrity check
```

### 3.2 Mobile-to-ESP32 JSON Format (Sent over BLE)
```json
{
  "emergency_id": "SOR100001",
  "person_id": "GUEST_A9F2",
  "person_name": "Rohan Sharma",
  "phone": "+919876543210",
  "latitude": 12.914142,
  "longitude": 74.856012,
  "accuracy": 4.5,
  "emergency_type": "MEDICAL",
  "message": "Immediate oxygen support required",
  "communication_method": "BLUETOOTH_LORA",
  "status": "TRANSMITTING",
  "timestamp": "2026-11-04T17:45:00Z",
  "hop_count": 0
}
```

### 3.3 ESP32-to-Mobile ACK Response (Received via BLE Notify)
```json
{
  "event": "LORA_ACK",
  "emergency_id": "SOR100001",
  "node_id": "ESP32_RELAY_4B",
  "gateway_reached": false,
  "hop_count": 1,
  "rssi": -88,
  "snr": 7.5,
  "status": "RELAYED",
  "timestamp": "2026-11-04T17:45:12Z"
}
```

---

## 4. Relay Forwarding & Anti-Collision Mechanism

1. **Duplicate Detection Cache**:
   Each ESP32 node maintains a circular ring buffer of the last 64 seen `(emergency_id, sequence)` hashes. If a received packet exists in the buffer, it is dropped immediately.
2. **Hop Count / TTL Limit**:
   Each relay node increments `hop_count`. If `hop_count >= MAX_HOPS` (5), the packet is not forwarded further.
3. **Random Backoff (Jitter)**:
   Relay nodes delay retransmission by `random(300ms, 1200ms) * hop_count` to prevent RF packet collision between synchronized receivers.
4. **Gateway Delivery**:
   Once any relay node with active cellular (LTE-M/NB-IoT) or Wi-Fi connectivity receives the packet, it POSTs the packet to Supabase `submit_sos_alert` RPC endpoint and transmits a LoRa downlink ACK packet.

---

## 5. Software Abstraction in SORYNTH App

The mobile application architecture uses a strict separation between mock simulation and physical hardware:
- **`BluetoothService`**: Core interface.
- **`MockEsp32BluetoothService`**: Simulates BLE discovery, pairing, transmission delay, LoRa relay hops, RSSI fluctuations, and downlink ACK. Clearly flagged in the UI as **`[SIMULATED ESP32 NODE]`**.
- **`FlutterBluePlusBluetoothService`**: Production driver interacting with real ESP32 hardware when connected.
- **`NeverFakeDeliveryRule`**: The UI never marks an emergency as `DELIVERED` or `ACKNOWLEDGED` until verified by a response code from Supabase or LoRa downlink.

