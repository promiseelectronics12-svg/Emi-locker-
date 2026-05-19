# EMI Locker API Route Index

This index records the routes that connect the dealer app, backend, user app, and admin surfaces. Keep this file updated whenever a route is added, removed, renamed, or changes response shape.

Current architecture decisions and superseded plans are documented in `docs/CURRENT_ARCHITECTURE_AND_SUPERSEDED_PLANS.md`.

## Backend Base

| Item | Value |
| --- | --- |
| Render backend | `https://emi-locker-erkt.onrender.com` |
| API prefix | `/api/v1` |
| Dealer auth | `Authorization: Bearer <dealer_jwt>` |
| Device auth | `x-device-token: <device_jwt>` |
| Real-time dealer channel | `/api/v1/events` SSE |

## Critical Dealer Routes

| Flow | Method | Route | Dealer app expectation | Backend responsibility |
| --- | --- | --- | --- | --- |
| Dealer dashboard devices | GET | `/api/v1/dealer/devices` | Device list with lock, EMI, health, last location summary | Return dealer-owned devices only |
| Device lock detail | GET | `/api/v1/dealer/devices/:deviceId/lock-detail` | Current lock state, pending actions, offline unlock status | Merge DB state and latest device reports |
| Lock device | POST | `/api/v1/lock/:deviceId/lock` or dealer lock route | Return accepted/pending quickly | Record command and send FCM |
| Unlock device | POST | `/api/v1/lock/:deviceId/unlock` or dealer unlock route | Return accepted/pending quickly | Record command and send FCM |
| Pull location | POST | `/api/v1/location/:deviceId/pull` | Return pull id and accepted/pending state | Keep one active pull, expire old pulls, send FCM |
| Location history | GET | `/api/v1/location/:deviceId/history` | Map/history list | Return stored locations with timestamps and freshness |
| Dealer message | POST | `/api/v1/notifications/message` | Return sent/accepted status quickly | Validate ownership and dispatch FCM |
| Enrollment QR | POST | `/api/v1/dealer/enrollment-qr` | QR payload or readable setup error | Create AMAPI enrollment token |
| Dealer enrollment | POST | `/api/v1/dealer/enrollments` | Pending enrollment with code/QR | Store customer/device/EMI/evidence metadata |
| Evidence metadata | POST/GET | `/api/v1/evidence/...` | Encrypted vault status | Store references only, not raw private images |

## Critical User App Routes

| Flow | Method | Route | User app responsibility | Backend responsibility |
| --- | --- | --- | --- | --- |
| Pre-register | POST | `/api/v1/device-activation/pre-register` | Start activation | Create pre-registration state |
| Confirm binding | POST | `/api/v1/device-activation/confirm` | Send 6-digit code/device identifiers | Activate device, create schedule, return device token |
| Refresh device token | POST | `/api/v1/device-activation/:deviceId/refresh-token` | Recover missing local token | Verify device and issue token |
| FCM token update | POST | `/api/v1/device-activation/:deviceId/fcm` | Store current FCM token | Update device push target |
| Location report | POST | `/api/v1/location/:deviceId/report` | Send GPS result with `x-device-token` | Store location, complete pull, emit SSE |
| EMI schedule refresh | GET | `/api/v1/device/emi-schedule` | Sync active finite schedule | Return current active schedule |
| Heartbeat | POST | `/api/v1/device/heartbeat` | Report alive/permission/SIM/status on adaptive schedule | Update health and permission state; optionally return pending command hint |
| Runtime events | POST | `/api/v1/device-activation/:deviceId/events` | Report command results, permission changes, lock state | Persist actual device state and emit SSE |

## SSE Events To Maintain

| Event | Producer | Consumer | Required payload |
| --- | --- | --- | --- |
| `location_update` | Backend after device report | Dealer app device/location screens | `deviceId`, `pullId`, `latitude`, `longitude`, `accuracy`, `timestamp`, freshness |
| `lock_status_changed` | Backend after command result/status sync | Dealer app lock screens/device list | `deviceId`, `isLocked`, `lockLevel`, `source`, `timestamp` |
| `device_health_changed` | Backend after heartbeat/FCM invalid token | Dealer app list/detail | `deviceId`, `healthStatus`, `lastSeenAt`, `fcmTokenStatus` |

## Device Heartbeat Permission Fields

The user app may include these fields in `POST /api/v1/device/heartbeat`:

| Field | Meaning |
| --- | --- |
| `permission_health` | `healthy` or `degraded` |
| `permission_degraded_reasons` | Comma-separated reason codes |
| `permission_overlay` | Legacy/fallback overlay permission state; current primary lock path is kiosk/Device Owner |
| `permission_location` | Fine or coarse location available |
| `permission_background_location` | Background location available where Android requires it |
| `permission_sms` | SMS receive permission available |
| `permission_notifications` | Notification permission/channel available |
| `permission_device_admin` | Device admin active |
| `permission_device_owner` | Device owner mode active |
| `permission_battery_unrestricted` | Battery optimization ignored/unrestricted |
| `enrollment_confirmed` | Backend after user confirms code | Dealer app enrollment/inventory | `deviceId`, customer summary, schedule summary |
| `message_delivery_changed` | Backend/user app when available | Dealer message UI | `deviceId`, message id, accepted/delivered/failed |

## Risk Engine Routes (Stream C — 2026-05-19)

Auth: dealer/admin JWT. All under `/api/v1/risk/`.

| Method | Route | Role | Purpose |
|--------|-------|------|---------|
| GET | `/risk/:deviceId/score` | dealer, admin | Current risk score + signal breakdown + last 50 signals + last 20 lock decisions |
| POST | `/risk/:deviceId/signal` | admin | Record a signal manually (body: `{signalType, details}`) |
| DELETE | `/risk/:deviceId/signal/:signalType` | admin | Clear a resolved signal |
| POST | `/risk/:deviceId/evaluate` | admin | Force immediate lock-decision evaluation |

### SSE Events Added

| Event | Payload | Sent to |
|-------|---------|---------|
| `risk_score_changed` | `{deviceId, totalScore, signals, updatedAt}` | management + dealer |
| `risk_score_threshold` | `{deviceId, riskScore, signalBreakdown, windowExpiresAt, message}` | dealer |

## Route Hygiene Rules

1. Every command route must return a response within the API timeout.
2. A route that triggers FCM must return `accepted` even if device confirmation is pending.
3. Device-result routes must be protected by `x-device-token`.
4. Dealer routes must validate ownership using the dealer's user id and dealer profile id when legacy data may differ.
5. New response fields must be added to typed app models before UI usage.
