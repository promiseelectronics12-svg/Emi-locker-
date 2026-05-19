# EMI Locker System Map

This file is the living collaboration map for EMI Locker. Update it in the same change whenever backend routes, app flows, database tables, FCM commands, SSE events, or security assumptions change.

Current product decisions, including removed plans, live in `docs/CURRENT_ARCHITECTURE_AND_SUPERSEDED_PLANS.md`. If an older Markdown file conflicts with that document, treat the current architecture document as the source of truth.

## Ownership Model

| Area | Primary owner | Responsibility |
| --- | --- | --- |
| Product decisions | Founder / product owner | Payment rules, lock policy, dealer workflow, release approval |
| System building | Codex + builder | Implementation, architecture hygiene, documentation updates |
| Backend maintenance | Backend developer | Render service, API contracts, Neon schema, FCM/SSE command flow |
| Dealer app maintenance | Flutter developer | Dealer UX, command screens, real-time status, evidence capture |
| User app maintenance | Kotlin developer | Device command receiver, permissions, kiosk lock screen, adaptive heartbeat, offline SMS/OTP fallback |
| QC / field testing | Tester | Real-device test runs, fault reporting, permission tamper checks |

## Source Of Truth Rule

A code change is not complete unless the matching documentation is updated:

| Change type | Required docs |
| --- | --- |
| New backend route or response shape | `docs/API_ROUTE_INDEX.md` |
| New device command or SSE event | `docs/SYSTEM_MAP.md`, route-specific flow doc |
| New database table or column | `docs/DATABASE_SCHEMA_MAP.md` |
| New service tier behavior | `docs/THREE_TIER_SERVICE_GUIDE.md` |
| New bug, false fix, or production issue | `docs/FAULT_LEDGER.md` |
| New manual test case | `docs/qc/EMI_LOCKER_QC_MATRIX.csv` and workbook |

## High-Level Architecture

Three-app platform. All three share one Firebase project and one backend.

```mermaid
flowchart LR
  Dealer["Dealer App\nFlutter\ncom.emilocker.dealerapp"] -->|JWT API calls| Backend["Backend\nNode.js on Render"]
  Customer["EMI Locker\nCustomer App\ncom.emilocker.app"] -->|JWT + IMEI auth| Backend
  Backend -->|SQL| Neon["Neon PostgreSQL"]
  Backend -->|FCM data command| FCM["Firebase Cloud Messaging"]
  FCM --> DPS["DeviceProtectionService\nKotlin Android\nDevice Owner"]
  FCM --> Customer
  FCM --> Dealer
  DPS -->|x-device-token JWT + adaptive heartbeat| Backend
  Backend -->|SSE events| Dealer
  Dealer -->|Optional encrypted local backup| Drive["Dealer Google Drive\noptional workspace backup"]
```

## Current Product Architecture Summary

| Area | Current decision |
| --- | --- |
| Lock enforcement | One primary kiosk lock screen. Removable watermark/overlay is not the main enforcement path. |
| Runtime state | No separate `PARTIAL_LOCK` product path. Use normal, pending, locked, decoupled, fraud/risk, and history/reminder events. |
| Heartbeat | Adaptive 10-15 minute normal baseline; stationary/healthy may stretch to 20 min; alert mode 5 min; lockdown pending 3 min; SMS fallback rare and cost-aware. |
| Location | Phone-side meaningful timeline filtering; backend stores limited/capped points, not raw GPS streams. |
| SIM binding | Bound SIM must remain present; wrong/missing SIM triggers risk/lock after persisted grace. |
| Re-enroll | Reconnect and resale/clean-sheet are separate flows. Resale clean sheet requires admin approval. |
| Dealer onboarding | Production direction is invite-only dealer activation, not open signup. |
| Backup | Backend and company-controlled encrypted backups are source of truth; dealer Google backup is optional convenience. |

## Command Lifecycle Contract

Every command must have a visible terminal state in the dealer UI.

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Sending: dealer taps action
  Sending --> Accepted: backend accepts command
  Sending --> Failed: API error or validation error
  Accepted --> WaitingForDevice: FCM dispatched
  WaitingForDevice --> Confirmed: device reports result
  WaitingForDevice --> Pending: timeout without confirmation
  Pending --> Confirmed: later heartbeat/status sync
  Pending --> Expired: max wait exceeded
  Failed --> Idle
  Confirmed --> Idle
  Expired --> Idle
```

Required UI behavior:

| State | Dealer UI behavior |
| --- | --- |
| Sending | Disable button, show short progress text |
| Accepted | Show "request sent" immediately |
| WaitingForDevice | Poll or listen to SSE with max wait |
| Confirmed | Show final status and refresh device detail |
| Pending | Stop spinner; show "device has not confirmed yet" |
| Failed | Show readable error and allow retry |

## Main Runtime Flows

### Enrollment And EMI Schedule

```mermaid
sequenceDiagram
  participant D as Dealer App
  participant B as Backend
  participant DB as Neon DB
  participant U as User App

  D->>B: POST /api/v1/dealer/enrollments with EMI terms
  B->>DB: Store pending enrollment and EMI terms
  B-->>D: Binding code / QR data
  U->>B: POST /api/v1/device-activation/confirm
  B->>DB: Mark device active and create emi_schedules row
  B-->>U: device_token + emi_schedule
  U->>U: Expand finite local installment rows
  B-->>D: SSE enrollment/device update
```

IMEI capture rule:

| Source | System behavior |
| --- | --- |
| Dealer scan | Dealer app scans QR/barcode from phone box or sticker, extracts up to two valid 15-digit IMEIs, and pre-fills IMEI 1 / IMEI 2 |
| Dealer manual input | Dealer can type IMEI manually as fallback; app validates 15 digits plus Luhn checksum |
| User app hardware read | Optional only; modern Android often blocks IMEI access for normal apps |
| Backend validation | Enrollment API rejects invalid IMEI checksums and duplicate IMEI 1 / IMEI 2 |

### Pull Location

```mermaid
sequenceDiagram
  participant D as Dealer App
  participant B as Backend
  participant DB as Neon DB
  participant F as FCM
  participant U as User App

  D->>B: POST /api/v1/location/{deviceId}/pull
  B->>DB: Create/replace active pull request
  B->>F: Send GET_LOCATION data command
  F->>U: Deliver command
  U->>U: Verify command and read GPS
  U->>B: POST /api/v1/location/{deviceId}/report
  B->>DB: Store location and complete pull
  B-->>D: SSE location_update
  D->>D: Show map marker, accuracy circle, timestamp
```

### Lock / Unlock

```mermaid
sequenceDiagram
  participant D as Dealer App
  participant B as Backend
  participant DB as Neon DB
  participant F as FCM
  participant U as User App

  D->>B: POST lock/unlock action
  B->>DB: Record requested action
  B->>F: Send device command
  B-->>D: Return accepted status immediately
  F->>U: Deliver command
  U->>U: Apply kiosk lock / Device Owner behavior
  U->>B: POST command result / status sync
  B->>DB: Persist actual device state
  B-->>D: SSE lock_status_changed
  D->>D: Stop spinner and show final or pending state
```

### Permission Tamper Detection

```mermaid
sequenceDiagram
  participant U as User App
  participant B as Backend
  participant DB as Neon DB
  participant D as Dealer App

  U->>U: Check kiosk/location/SMS/notification/admin/battery/SIM state
  U->>B: POST /api/v1/device/heartbeat with permission snapshot
  B->>DB: Store online or degraded device health
  B-->>D: SSE device_health_changed
  D->>D: Show protection degraded warning
```

The user app reports permission health on app start, dashboard resume, foreground service start, FCM command handling, and scheduled heartbeat. Android does not provide one universal instant permission-change broadcast, so the app reports the change at the first reliable runtime touchpoint after tampering.

## Codebase Index

| Codebase | Path | Role |
| --- | --- | --- |
| Backend | `backend/` | API, DB access, FCM dispatch, SSE, auth, enrollment, lock/location/message flows |
| Dealer app | `dealer-app-v2/` | Flutter app used by dealers/resellers/admin-like roles |
| User app | `user-app/` | Kotlin Android collateral phone agent |
| Admin panel | `admin-panel/` | Web admin operations |
| Database docs/migrations | `database/`, `backend/src`, `backend/scripts` | Schema and migration history |
| Collaboration docs | `docs/` | Living maps, fault ledger, QC workbook |

## Service Tier Contract

Two tiers only: **Standard** and **Premium**. VIP is removed. Full behavior in `docs/THREE_TIER_SERVICE_GUIDE.md`.

Do not treat key tier as only a UI label. During confirmed enrollment, key/enrollment tier must become runtime service policy for backend scheduler, dealer UI, DeviceProtectionService behavior, and EMI Locker customer app push behavior.

```mermaid
flowchart LR
  Key["Activation Key\nstandard / premium"] --> Enrollment["Pending Enrollment"]
  Enrollment --> Confirm["Device Confirms Code"]
  Confirm --> Schedule["Active EMI Schedule\nservice_tier"]
  Schedule --> BackendPolicy["Backend Tier Policy"]
  BackendPolicy --> DealerUX["Dealer App Tier UI"]
  BackendPolicy --> DPS["DeviceProtectionService\nEnforcement Layer"]
  BackendPolicy --> CustomerPush["EMI Locker Customer App\nPremium push only"]
```

## Risk Engine (Stream C — 2026-05-19)

Lock rule: `overdue_emi && risk_score >= 6 && dealer_notification_window_expired (2h)`.
Single signal never auto-locks. Every evaluation written to `auto_lock_decisions`.

- `backend/src/modules/risk/riskService.js` — `recordSignal()`, `removeSignal()`, `evaluateLockDecision()`
- `backend/src/modules/risk/riskScheduler.js` — every 3 min rescore SIM-missing; every 5 min evaluate overdue devices
- Replaced `fraudScheduler.runSimMissingCheck()` — SIM absence now a time-escalating risk signal, not a direct lock trigger
- Signal weights: sim_missing (4→6→8 over time), heartbeat_missing (4→6→8), emi_locker_admin_revoked (3), gmail_mismatch (2), boot_after_shutdown (1)

## Known Architecture Risks

| Risk | Why it matters | Guardrail |
| --- | --- | --- |
| Dealer monolith file | Too many flows in one file hides bugs | Split by feature after critical timeouts/logging |
| Silent catches | Errors disappear and UI spins | No `catch (_) {}` without logging |
| No command ceiling | UI can wait forever | Every action has timeout and pending state |
| Permission tampering | User app can become ineffective | User app must detect missing permissions and report degraded status |
| Stale location | Dealer may think old data is live | Every location must show freshness and timestamp |
| Offline device | Commands cannot complete instantly | Dealer UI must distinguish accepted, pending, confirmed |
