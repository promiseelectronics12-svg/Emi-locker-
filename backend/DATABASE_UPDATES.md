# Database Schema Updates

## Migration 100: Dealer Device Settings (`100_dealer_device_settings.sql`)

This update introduces per-dealer and per-device configuration for offline resilience and lock-screen behavior. 

### 1. `dealer_device_settings` Table
Stores granular, device-level overrides for how a specific enrolled device behaves.
- **Foreign Keys**: `device_id` (UUID, UNIQUE, CASCADE), `dealer_id` (UUID).
- **Offline Resilience**:
  - `offline_grace_hours` (24 - 168 hours, default 72)
  - `warning_threshold_hours` (1 - 48 hours, default 12)
  - `checkin_interval_minutes` (60 - 1440 mins, default 360)
- **Lock Screen Branding**:
  - `lock_screen_message` (up to 200 chars)
  - `lock_screen_dealer_name` (up to 80 chars)
  - `lock_screen_dealer_phone` (up to 20 chars)
- **Lock Behavior**:
  - `default_lock_level` (ENUM 'SOFT' or 'FULL', default 'FULL')

### 2. `dealer_defaults` Table
Stores the global defaults for a specific dealer. These apply to new device enrollments unless explicitly overridden by `dealer_device_settings`.
- **Primary Key**: `dealer_id`
- Contains identical columns to `dealer_device_settings` for offline limits, lock screen branding, and default lock level.

### Backend API Implications
- **Device Enrollment**: When a device registers, the backend should query `dealer_defaults` and apply them to the device.
- **App Policy Push**: The parameters (grace period, warning threshold) need to be included in the FCM policy payload sent to the Flutter/Android apps.
- **Lock Commands**: The lock screen branding info must be attached to the lock payload if `FULL` lock is engaged.

## Migrations 101-108: Advanced Device Security and Anomaly Detection
Recent migrations added tables to support advanced device security features, location tracking, and dealer intelligence.
- `101_grace_unlock.sql` - Offline token usage logs.
- `102_device_grace_expires.sql` - Grace period expiration schedules.
- `103_sim_events.sql` - SIM change anomaly tracking.
- `104_location_anomalies.sql` - Geofence violation and anomaly detection.
- `105_credit_scores.sql` - Dealer credit scoring logic.
- `106_evidence_vault.sql` - Store photos and logs of device tampering.
- `107_theft_protection.sql` - Stolen device marking and theft workflows.
- `108_profile_seeds.sql` - Initial seed data for test profiles.
