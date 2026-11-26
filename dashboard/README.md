# SORYNTH – Rescue Command Dashboard

> **Signal Beyond Boundaries**

Production-grade web command & dispatch dashboard for **SORYNTH** — Hybrid Internet and LoRa-Based Emergency SOS Communication System.

Used by emergency response commanders, dispatchers, and rescue teams to monitor incoming SOS requests, victim locations, communication links, and off-grid LoRa relay networks in real-time.

---

## 1. Tech Stack

- **Framework**: React 19 + TypeScript + Vite
- **Styling**: Tailwind CSS (Dark Military Navy & Electric Cyan Tactical Command Theme)
- **Icons**: Lucide React
- **Backend & Realtime**: `@supabase/supabase-js` (PostgreSQL + Realtime WebSocket)
- **Data Visualization**: Recharts
- **Geospatial Mapping**: Leaflet + React-Leaflet + CartoDB Dark Matter Tiles
- **Routing**: React Router v7

---

## 2. Dashboard Modules & Pages

1. **Overview Dashboard (`/`)**
   - 6 Live KPI Cards: Active Emergencies, Total Emergencies, Resolved Emergencies, Available Rescue Teams, Verified Relay Nodes, and Average Response Time.
   - Recent SOS emergency feed with live status badges.
   - Emergency category breakdown donut chart (Medical, Accident, Fire, Natural Disaster, Lost/Stranded, Other).
   - Emergency status lifecycle bar chart (RECEIVED, ACKNOWLEDGED, RESPONDING, RESOLVED, CANCELLED).
   - Dual-tier communication health monitor.
   - Operational audit timeline stream.

2. **Live Emergencies (`/emergencies`)**
   - Complete incident registry with multi-criteria search and filters:
     - Search by Incident Code, victim name, phone, message text.
     - Filter by Status, Incident Type, Communication Channel, and Account Mode (Guest vs Registered).
     - Sort by Newest, Oldest, Status, Type.
   - Slide-over Emergency Detail Drawer:
     - Incident metadata, precise GPS coordinates, and GPS fix accuracy badge (`±Xm`).
     - Victim contact details and custom distress message.
     - Authorized rescue operator action buttons: **ACKNOWLEDGE**, **DISPATCH RESCUE TEAM**, **RESOLVE**, and **CANCEL**.
     - Rescue team assignment dropdown.
     - Incident audit timeline from `public.emergency_updates`.

3. **Emergency Geospatial Map (`/map`)**
   - Full-screen tactical dark map rendered via Leaflet & OpenStreetMap.
   - Real-time SOS pins color-coded by incident severity and response state.
   - Pulsing tactical auras and GPS accuracy circles.
   - Real rescue team station markers from `public.rescue_teams`.
   - Side incident queue with instant map panning and click-to-inspect popups.
   - **Zero demo/fake coordinate fabrication**: only genuine backend fixes are plotted.

4. **LoRa Relay Network (`/network`)**
   - Real-time monitoring of ESP32 master transceivers and mesh relay nodes.
   - Gateway connection health and telemetry ingestion metrics.
   - Hardware status rule enforcement: When hardware has not reported packets yet, prominently displays:
     > *"Hardware integration pending – awaiting real gateway data."*
     *(Never displays fake online nodes).*
   - Node signal telemetry: Average RSSI (dBm), Average SNR (dB), hop count, packet counts.
   - Full hardware specification architecture reference (Semtech SX1276/SX1262, Nordic UART BLE GATT `6E400001`, 32-byte binary payload, 5 max hops).

5. **Communication Monitor (`/comms`)**
   - Protocol health tracking across Internet/Supabase, BLE ESP32, LoRa Radio, and Multi-Hop Forwarding.
   - Strict distinction of lifecycle states:
     - `UPLOADED TO SERVER`
     - `GATEWAY RECEIVED`
     - `QUEUED LOCALLY (PENDING HARDWARE TRANSMISSION)`
     - `TRANSMITTING VIA LORA / RELAYED`
   - Complete visual dual-tier topology pipeline from mobile trigger to command dashboard dispatch.

6. **Rescue Teams (`/teams`)**
   - Registered field units from `public.rescue_teams`.
   - Team status badges (`ACTIVE`, `ON_MISSION`, `STANDBY`) with one-click readiness toggling.
   - Jurisdiction sector, dispatch phone contact, and live count of assigned emergencies.
   - New rescue unit registration modal.

7. **Analytics & Reports (`/analytics`)**
   - Multi-day trend analysis (Past 7, 14, 30 days) with Recharts area chart.
   - Category distribution and communication channel utilization charts.
   - Performance metrics (Resolution Ratio, Guest SOS Ratio, Mesh Relay traffic).
   - One-click **Export to CSV** and **JSON Telemetry Dump**.

8. **Settings (`/settings`)**
   - Supabase connection endpoints and publishable anon key status.
   - Live backend diagnostic test suite (tests REST connectivity, RPC functions, and table RLS policies).
   - Synthesized Web Audio SOS tactical alarm toggle.
   - Current operator clearance credentials and role summary.
   - Supabase SQL Setup Script (`src/sql/operator_dashboard_setup.sql`) with one-click copy.

---

## 3. Quick Start & Execution

### Prerequisites

- Node.js 18+ (tested with v26)
- npm 9+

### Commands

```bash
# 1. Install dependencies
npm install

# 2. Start development server
npm run dev

# 3. Build for production
npm run build

# 4. Preview production build
npm run preview
```

The application runs on `http://localhost:5173` (or `http://localhost:4173` for preview).

---

## 4. Supabase Backend Integration & Security

### Target Supabase Instance

- **Project URL**: `https://pmkwudzlyvaegwmugmoy.supabase.co`
- **Publishable Key**: `sb_publishable_g9JmugniAZgkgz4LSKgRHg_cEsJsnpD`

### Security & RLS Architecture

- **Row Level Security (RLS)** is enabled across all tables (`profiles`, `emergencies`, `emergency_updates`, `relay_logs`, `rescue_teams`).
- The dashboard operates strictly through the client anon key with user authentication or secure stored procedures (RPC).
- Secret service-role keys are **never** bundled or exposed in client code.
- To configure rescue operator clearance in your Supabase project, execute `src/sql/operator_dashboard_setup.sql` in the Supabase SQL Editor. This grants operators full command visibility without modifying or breaking the mobile app's citizen privacy policies.

---

## 5. File Structure

```text
SORYNTH-DASH/
├── index.html                       # HTML5 entry with tactical metadata and fonts
├── package.json                     # Project scripts and dependencies
├── tailwind.config.js               # Tactical military navy & electric cyan theme
├── vite.config.ts                   # Vite bundler configuration
├── src/
│   ├── main.tsx                     # React root mount
│   ├── App.tsx                      # Application Router & Global Providers
│   ├── index.css                    # Tailwind directives & Leaflet styling
│   ├── types/
│   │   └── index.ts                 # Database models, enums & filter types
│   ├── services/
│   │   ├── supabaseClient.ts        # Supabase client & diagnostic tests
│   │   ├── emergencyService.ts      # Emergencies CRUD, RPC & Realtime
│   │   ├── rescueTeamService.ts     # Team registration & management
│   │   ├── loraService.ts           # LoRa node analysis & packet logs
│   │   └── analyticsService.ts      # Recharts aggregations & CSV export
│   ├── context/
│   │   ├── AuthContext.tsx          # Operator authentication & session state
│   │   └── EmergencyContext.tsx      # Global emergency state & Web Audio alarm
│   ├── sql/
│   │   └── operator_dashboard_setup.sql # Operator RLS migration script
│   ├── components/
│   │   ├── layout/
│   │   │   └── DashboardLayout.tsx  # Responsive sidebar, header & outlet
│   │   ├── common/
│   │   │   ├── Sidebar.tsx          # Tactical navigation with live counters
│   │   │   ├── CommandHeader.tsx    # Clock, status pill, audio toggle
│   │   │   ├── StatusBadge.tsx      # Color-coded tactical badges
│   │   │   ├── GlassCard.tsx        # Reusable glassmorphism card
│   │   │   ├── EmptyState.tsx       # Standard empty & pending states
│   │   │   └── ProtectedRoute.tsx   # Auth guard for operator routes
│   │   ├── dashboard/
│   │   │   ├── KpiGrid.tsx          # 6 high-density KPI cards
│   │   │   ├── RecentSosTable.tsx   # Latest incident feed
│   │   │   ├── CategoryChart.tsx    # Incident type donut chart
│   │   │   ├── StatusChart.tsx      # Lifecycle progression bar chart
│   │   │   ├── CommStatusWidget.tsx # Communication link health
│   │   │   └── SystemActivityTimeline.tsx # Audit timeline stream
│   │   ├── emergencies/
│   │   │   ├── EmergencyTable.tsx   # Incident management table
│   │   │   ├── EmergencyFilterBar.tsx # Search & filter dropdowns
│   │   │   └── EmergencyDetailDrawer.tsx # Operator action drawer
│   │   ├── map/
│   │   │   └── TacticalMap.tsx      # Interactive Leaflet dark command map
│   │   ├── network/
│   │   │   └── LoraRelayDashboard.tsx # Node telemetry & pending banner
│   │   ├── comms/
│   │   │   └── CommunicationMonitor.tsx # State machine & topology
│   │   └── teams/
│   │       └── RescueTeamManager.tsx # Rescue units list & registration
│   └── pages/
│       ├── OverviewPage.tsx
│       ├── LiveEmergenciesPage.tsx
│       ├── EmergencyMapPage.tsx
│       ├── RelayNetworkPage.tsx
│       ├── CommMonitorPage.tsx
│       ├── RescueTeamsPage.tsx
│       ├── AnalyticsPage.tsx
│       ├── SettingsPage.tsx
│       └── LoginPage.tsx
```

---

## 6. Verification Status

- [x] TypeScript compiler check: `0 errors`
- [x] Production build: `vite build` completed successfully
- [x] HTTP asset loading: All JS and CSS bundles return HTTP 200 OK
- [x] Live Supabase backend verified: `https://pmkwudzlyvaegwmugmoy.supabase.co` connected
- [x] Flutter mobile application kept completely separate in `../SORYNTH-APK` with zero file modifications
