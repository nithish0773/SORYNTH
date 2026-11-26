# SORYNTH

> **SIGNAL BEYOND BOUNDARIES**  
> *Hybrid Internet and LoRa-Based Emergency SOS Communication System*

---

## 1. Project Overview

**SORYNTH** is a life-critical Android emergency response application engineered to broadcast SOS distress signals and high-precision GPS coordinates to rescue coordinators, even when conventional cellular towers and Wi-Fi networks have completely failed due to natural disasters, terrain isolation, or infrastructure collapse.

The system features an autonomous dual-engine failover mechanism:
1. **Online Mode (Supabase Realtime)**: When internet connectivity is active, distress signals are encrypted and transmitted via HTTPS/PostgreSQL RPC directly to the SORYNTH rescue cloud.
2. **Offline Mode (ESP32 + LoRa Mesh Relay)**: When internet connectivity is unavailable, the application immediately activates a local Bluetooth Low Energy (BLE) link to an external ESP32 transceiver. The transceiver packages the alert into a compact 32-byte binary radio frame and broadcasts it across an 868MHz/915MHz LoRa multi-hop mesh network until reaching an internet-connected gateway.
3. **Guest SOS (Zero Barrier to Rescue)**: Civilians can broadcast full GPS emergency alerts instantly with a single tap or hold, without registration, login, or personal data hurdles.

---

## 2. Technology Stack

- **Framework**: Flutter 3.47+ (Dart 3.13+)
- **Design System**: Material 3 (Apple-level simplicity + emergency response clarity)
- **State Management**: Flutter Riverpod (`flutter_riverpod: ^2.6.1`)
- **Navigation**: Declarative GoRouter (`go_router: ^14.8.1`)
- **Backend & Realtime**: Supabase (`supabase_flutter: ^2.8.4`, PostgreSQL with Row-Level Security)
- **Geolocation**: Geolocator (`geolocator: ^13.0.2`) with high-accuracy GPS fix and caching
- **Hardware Integration**: Flutter Blue Plus (`flutter_blue_plus: ^1.35.3`) with clean abstraction
- **Local Persistence**: Shared Preferences & Flutter Secure Storage (persistent offline message queue)
- **Connectivity Detection**: Connectivity Plus (`connectivity_plus: ^6.1.4`) with active DNS reachability probes

---

## 3. Application Architecture

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart          # Semantic palette (Primary Blue #1463D9, SOS Red #E63946, Dark Navy #102438)
│   │   └── app_constants.dart       # Enums (EmergencyType, Status, CommMethod), UUIDs, Specs
│   ├── providers/
│   │   └── app_providers.dart       # Riverpod providers, notifiers, telemetry streams
│   ├── routing/
│   │   └── app_router.dart          # GoRouter declaration with type-safe arguments
│   └── theme/
│       └── app_theme.dart           # Clean M3 theme, rounded surfaces, accessible typography
│
├── data/
│   ├── models/
│   │   ├── emergency_model.dart     # Core SOS packet model & LoRa compact payload encoder
│   │   └── user_profile.dart        # Registered user medical & emergency contact schema
│   ├── repositories/
│   │   └── emergency_repository.dart# Dual-engine dispatch pipeline (Internet -> BLE -> LoRa)
│   └── services/
│       ├── bluetooth_service.dart   # Abstract BLE interface, MockEsp32Service & FlutterBluePlusService
│       ├── connectivity_service.dart# Active socket reachability detection
│       ├── gps_service.dart         # High-accuracy GPS locking and permission management
│       ├── offline_storage_service.dart # Durable offline queue (preserves SOS across restarts)
│       └── supabase_service.dart    # Cloud RPC caller, Auth, and Realtime listeners
│
├── features/
│   ├── splash/                      # Animated wireless pulse on dark navy
│   ├── onboarding/                  # 3-slide guide with indicators
│   ├── welcome/                     # Prominent Guest SOS + Registered User sign-in
│   ├── authentication/              # Login, registration, password reset
│   ├── guest_sos/                   # No-login emergency dispatch with crisis categorization
│   ├── home/                        # Radar status chips, press-and-hold SOS button
│   ├── emergency/                   # Step-by-step transmission telemetry pipeline
│   ├── tracking/                    # Real-time radar visualization & coordinates display
│   ├── history/                     # Filterable log (All, Active, Resolved)
│   └── profile/                     # Medical info, contacts, and ESP32 simulation toggle
│
└── shared/widgets/                  # Logo, SOS button with progress ring, Status badges, Banners
```

---

## 4. Hardware Integration: ESP32 + LoRa Transceiver

Physical hardware has been fully abstracted into an interface (`BluetoothService`), allowing development and UI testing before physical PCB delivery:

- **Mock ESP32 Service (`MockEsp32BluetoothService`)**:
  Simulates device pairing, GATT characteristic writes, LoRa multi-hop packet propagation through simulated relay nodes (`ESP32_RELAY_02` -> `ESP32_GW_ALPHA`), and downlink ACK verification.
  - Transparently marked in UI with `[SIMULATED ESP32 NODE]` chips.
  - Can be toggled on/off in the Profile screen or top app bar.
- **Production BLE Service (`FlutterBluePlusBluetoothService`)**:
  Ready for physical ESP32 transceivers. Scans for Nordic UART GATT service UUID `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, sends 32-byte compact payloads, and awaits asynchronous ACK packets.
- **No False Deliveries**:
  Per project specifications, the application **never** displays a fake `DELIVERED` status. Packets stay `STORED` or `TRANSMITTING` until verified by a server HTTP 200 response or LoRa gateway downlink ACK.

---

## 5. Supabase Database & Security Setup

1. Open your project on the [Supabase Dashboard](https://supabase.com/dashboard) (Project: `sorynth`).
2. Navigate to the **SQL Editor**.
3. Open `supabase/migrations/20261104000001_sorynth_initial_schema.sql` and run it.
4. Tables created:
   - `profiles`: User details, blood group, medical notes, emergency contacts (Row Level Security protected).
   - `emergencies`: Core SOS storage, coordinates, communication route, status tracking.
   - `emergency_updates`: Real-time status change log and rescue team assignment timeline.
   - `relay_logs`: LoRa node telemetry (RSSI, SNR, hop count).
   - `rescue_teams`: Registered emergency response teams.
5. Functions & Anti-Spam:
   - `submit_sos_alert`: Stored Procedure (`SECURITY DEFINER`) that allows guest SOS alerts with strict coordinate bounds (`-90..90`, `-180..180`) and prevents spam/table scraping.
   - `get_emergency_status`: Allows guest users with an `emergency_code` to read only their own emergency status.
   - `cancel_emergency`: Safely marks emergency as cancelled.

---

## 6. How to Build the Android APK

### Prerequisites
- Flutter SDK 3.47+
- Android SDK Platform 34 or 36
- JDK 17 or 21

### Step 1: Run Static Analysis & Tests
```bash
flutter analyze
flutter test
```

### Step 2: Build Release APK
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL="https://your-sorynth-ref.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="your-anon-publishable-key"
```

The compiled release APK will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 7. Status & Deliverables Summary

| Feature Area | Status | Notes |
|---|---|---|
| **Guest SOS** | Completed | Fully functional without login or registration |
| **Registered User Auth** | Completed | Supabase Auth (Sign In, Sign Up, Password Reset) |
| **GPS Location Engine** | Completed | Geolocator high accuracy with fallback and permission handling |
| **Dual Transmission Pipeline** | Completed | Internet -> BLE -> LoRa multi-hop fallback |
| **Offline Message Persistence** | Completed | Queued locally; automatically flushed when internet returns |
| **LoRa Simulation Engine** | Completed | Step-by-step relay simulation with RSSI & hop telemetry |
| **Hardware BLE Driver** | Architecture Ready | `FlutterBluePlusBluetoothService` awaiting physical PCB |
| **UI Design System** | Completed | Apple-inspired clean M3 theme, animated radar, status chips |
| **Supabase Migrations** | Completed | SQL script with RLS, enums, triggers, and RPC procedures |
