# SORYNTH - Supabase Configuration & Execution Guide

## 1. Project Information
- **Supabase Project Name**: `sorynth`
- **Application Type**: Hybrid Internet + LoRa Emergency Response System

---

## 2. Executing Migrations in Supabase

### Option A: Via Supabase Web Dashboard (Recommended)
1. Log in to the [Supabase Dashboard](https://supabase.com/dashboard).
2. Open your project named **`sorynth`**.
3. In the left navigation bar, click on **SQL Editor**.
4. Click **New query**.
5. Copy the entire contents of `supabase/migrations/20261104000001_sorynth_initial_schema.sql`.
6. Paste the SQL into the editor window.
7. Click the **Run** button (or press `Ctrl+Enter` / `Cmd+Enter`).
8. Ensure the output displays:
   `Success. No rows returned` or list of created tables/functions.

### Option B: Via Supabase CLI (if installed locally)
```bash
supabase db push
# or
supabase db execute --file supabase/migrations/20261104000001_sorynth_initial_schema.sql
```

---

## 3. Environment Variables Configuration

In the SORYNTH Flutter mobile application, secrets are **never hardcoded** and service-role keys are **never bundled in the client APK**.

Create an `.env` file in the root of the project (or pass `--dart-define` at build time):

```env
SUPABASE_URL=https://your-sorynth-project-ref.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.your-anon-publishable-key
```

### Passing at Build Time (Preferred for Release APK)
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL="https://your-sorynth-project-ref.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="your-publishable-anon-key"
```

The Flutter application automatically checks for `--dart-define` values first, then falls back to `AppConfig` defaults for local offline development.

---

## 4. Database Security Architecture

| Table | RLS Status | Authenticated User Access | Guest User Access |
|---|---|---|---|
| `profiles` | ENABLED | View & edit own profile (`auth.uid() = id`) | None |
| `emergencies` | ENABLED | View & update own alerts (`auth.uid() = user_id`) | Indirect via `submit_sos_alert` RPC & `get_emergency_status` RPC |
| `emergency_updates` | ENABLED | View status updates of owned alerts | Read timeline for owned emergency |
| `relay_logs` | ENABLED | Gateway / Rescue Team view | Insert via LoRa Gateway node |
| `rescue_teams` | ENABLED | Rescue coordinators & responders | Read-only basic info |

### Anti-Spam & Guest Protection
- Guest users do not have raw `INSERT` permissions on the `emergencies` table.
- All guest emergency alerts are submitted via the `submit_sos_alert` RPC function with `SECURITY DEFINER`.
- The function enforces strict coordinate bounds (`-90 <= lat <= 90`, `-180 <= lng <= 180`), prevents duplicate emergency IDs, and records an audit log in `emergency_updates`.

