# EMI LOCKER PLATFORM — GRAPHIFY
> Machine-readable system map. Any AI model reads this instead of the full codebase.
> Last updated: 2026-05-03 | Maintained by: Claude (Primary Supervisor)

---

## 1. SYSTEM PURPOSE

Android MDM platform for EMI phone financing in Bangladesh.
- Dealers sell phones on installment via EMI
- Backend enrolls phone as Device Owner via Android Management API (AMAPI)
- Phone locks progressively when payments are missed (SOFT_LOCK → PARTIAL_LOCK → FULL_LOCK)
- Phone is fully decoupled (DPC removed, FRP cleared) when final payment is confirmed by admin

**Stakeholders:** Admin → Reseller → Dealer → Customer (phone owner)

---

## 2. ARCHITECTURE GRAPH

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENTS                                  │
│  [React Admin Panel]  [Flutter Dealer App]  [Kotlin User App]  │
│     :5173 (Vite)          :3000 (API)           :3000 (API)    │
└──────────────┬──────────────────┬──────────────────┬───────────┘
               │                  │                  │
               ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Node.js + Express API  (:3000)                 │
│  backend/src/index.js  →  backend/src/modules/index.js         │
│                                                                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │   auth   │ │ devices  │ │   lock   │ │  notifications   │  │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────────────┤  │
│  │   emi    │ │   keys   │ │ decoupl. │ │     location     │  │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────────────┤  │
│  │  admin   │ │  fraud   │ │          │ │                  │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │
└────────┬───────────────┬──────────────────────┬────────────────┘
         │               │                      │
         ▼               ▼                      ▼
   [PostgreSQL]       [Redis]           [Firebase / AMAPI]
   AES-256 at rest   Sessions/Rate      FCM push + Device Policy
                     limiting
```

---

## 3. MODULE REGISTRY

### PHASE 1 — FOUNDATION (all completed, pre-strict-scoring era)
> ⚠ These modules were approved under old threshold (score ≥ 60). Re-audit needed with new 95+ standard.

#### `backend/src/modules/auth/`
**Purpose:** JWT auth, TOTP 2FA, RBAC middleware
**Files:** `jwt.js` · `totp.js` · `rateLimit.js` · `index.js`
**Exports:** `generateToken()` · `verifyToken()` · `requireRole(role)` · `require2FA()`
**Endpoints:** `POST /auth/login` · `POST /auth/2fa/verify` · `POST /auth/refresh` · `POST /auth/logout`
**Depends on:** Redis (sessions), PostgreSQL (users table)
**Security rules:** RS256 JWT · 15min access token · 7day refresh · bcrypt cost 12 · rate limit 5/15min/IP
**Score:** 62 (old threshold) ⚠ NEEDS RE-AUDIT

#### `backend/src/modules/devices/`
**Purpose:** AMAPI device enrollment, hardware binding, command signing
**Files:** `deviceService.js` · `deviceController.js` · `deviceRoutes.js` · `device.repository.js` · `amapiService.js` · `commandSigningService.js` · `firebaseService.js` · `hardwareBindingService.js` · `kmsSigningService.js` · `index.js`
**Exports:** `DeviceService` · `AmapiService.enrollDevice()` · `CommandSigningService.sign()` · `FirebaseService.send()`
**Endpoints:** `POST /devices/enroll` · `GET /devices/:id` · `POST /devices/:id/heartbeat` · `GET /devices` · `DELETE /devices/:id`
**Depends on:** AMAPI (Google), Firebase Admin SDK, PostgreSQL (devices table), KMS/HSM
**Score:** 95 ✓

#### `backend/src/modules/lock/`
**Purpose:** Progressive lock state machine — 3-channel delivery
**Files:** `lockService.js` · `lockCommandService.js` · `lockDeliveryService.js` · `lockSchedulerService.js` · `lockVerificationService.js` · `pautService.js` · `padtService.js` · `lockController.js` · `lockRoutes.js` · `index.js`
**Exports:** `LockService.requestLock(deviceId, level)` · `LockService.requestUnlock(deviceId)` · `PautService.issue()` · `PadtService.issue()`
**Lock levels:** `SOFT_LOCK` (payment reminder overlay) → `PARTIAL_LOCK` (calls only) → `FULL_LOCK` (locked + GPS every 6h)
**Delivery channels:**
  1. FCM push (primary)
  2. AMAPI policy push (secondary — bypasses FCM)
  3. PAUT/PADT token on device (offline resilience — JWT, HMAC-signed)
**Endpoints:** `POST /lock/:deviceId` · `POST /lock/:deviceId/unlock` · `POST /lock/paut` · `POST /lock/padt`
**Score:** 92 ✓

#### `backend/src/modules/emi/`
**Purpose:** EMI schedule, payment recording, overdue detection, grace periods
**Files:** `emiService.js` · `emiController.js` · `emiRoutes.js` · `emiModel.js` · `emiValidation.js` · `decouplingService.js` · `index.js`
**Exports:** `EmiService.createSchedule()` · `EmiService.recordPayment()` · `EmiService.getOverdueStatus()` · `EmiService.triggerDecoupling()`
**Endpoints:** `POST /emi/schedule` · `GET /emi/:deviceId` · `POST /emi/:deviceId/payment` · `GET /emi/:deviceId/overdue-status` · `POST /emi/:deviceId/grace-period` · `GET /emi/upcoming`
**Depends on:** PostgreSQL (emi_schedules, emi_payments tables), decoupling module
**Score:** 75 (old threshold) ⚠ NEEDS RE-AUDIT

#### `backend/src/modules/notifications/`
**Purpose:** FCM push, SMS fallback, dealer overlay messages
**Files:** `fcm.service.js` · `notification.service.js` · `notification.repository.js` · `notification.routes.js` · `dealer-message-rate-limiter.js` · `sms.service.js` · `index.js`
**Exports:** `NotificationService.sendToDevice()` · `NotificationService.sendLockCommand()` · `NotificationService.sendUnlockCommand()` · `NotificationService.sendReminder()` · `NotificationService.sendDealerMessage()`
**Rate limiting:** Max 10 dealer messages/device/day (Redis enforced)
**SMS fallback:** Twilio — fires on lock/unlock confirmation when FCM fails
**Endpoints:** `POST /notifications/message`
**Score:** 82 (old threshold) ⚠ NEEDS RE-AUDIT

#### `database/migrations/`
**Tables:**
| File | Table | Key fields |
|------|-------|-----------|
| 001_users.sql | users | id, email, phone, role(ENUM), password_hash, totp_secret, status |
| 002_devices.sql | devices | id, imei, serial, soc_model, customer_id, dealer_id, state(ENUM), amapi_device_id, fcm_token |
| 003_activation_keys.sql | activation_keys | id, key_value, reseller_id, dealer_id, device_id, status(ENUM), expires_at, hmac_sig |
| 004_emi_schedules.sql | emi_schedules | id, device_id, total_amount, emi_amount, duration_months, grace_days, status |
| 005_emi_payments.sql | emi_payments | id, emi_id, device_id, amount, payment_date, method, tx_id, status |
| 006_lock_requests.sql | lock_requests | id, device_id, dealer_id, reason_code(ENUM), status, server_verdict |
| 007_decoupling.sql | decoupling | id, device_id, emi_id, state(ENUM), dealer_notified_at, fraud_flag, rtoc_code |
| 008_audit_log.sql | audit_log | id, actor_id, action, details_json, ip, timestamp — NO UPDATE/DELETE (trigger enforced) |
| 009_security_events.sql | security_events | id, device_id, event_type, severity, details_json, resolved |
| 010_paut_tokens.sql | paut_tokens | id, device_id, token_hash, action_type, expires_at, used |

---

### PHASE 2 — ADVANCED BACKEND (in progress — new 95+ scoring standard)

#### `backend/src/modules/keys/`
**Purpose:** HMAC-SHA256 activation key lifecycle — generate → assign → consume
**Files:** `keyService.js` · `keyController.js` · `keyRoutes.js` · `keyScheduler.js` · `hmac.service.js` · `schema.sql`
**Key format:** `XXXX-XXXX-XXXX-XXXX` (A-Z excl O/I/S + 2-9 excl 0/1/5 = ~77 bits entropy)
**Endpoints:** `POST /keys/request` · `POST /keys/approve/:requestId` · `POST /keys/assign` · `POST /keys/consume` (burns key to IMEI permanently)
**Rules:** Max 20% of monthly quota per request · 72h expiry · velocity check: 10+/24h triggers alert
**Score:** Completed (pre-strict) — being rebuilt under new standard

#### `backend/src/modules/decoupling/`
**Purpose:** Full decoupling state machine when EMI is fully paid
**Files:** `decouplingService.js` · `decouplingController.js` · `decouplingRoutes.js` · `decouplingScheduler.js` · `decouplingModel.js` · `schema.sql` · `index.js`
**State machine:**
```
EMI_ACTIVE → FINAL_PAYMENT_RECEIVED → DEALER_NOTIFIED → PENDING_ADMIN_DECOUPLE → DEVICE_DECOUPLED
                                             │
                                             └→ FRAUD_FLAGGED → FRAUD_CONFIRMED / FRAUD_REJECTED
```
**Key rules:**
- Dealer CANNOT block/delay decoupling — can only fraud-flag with evidence
- Admin executes decouple (requires 2FA) → generates RTOC → sends signed FCM command → calls AMAPI to delete managed account (clears FRP)
- If FCM fails: issue PADT (7 day expiry) — device checks on reconnect
- 5-day countdown timer after dealer notification (Bull queue)
**Score:** FAILED — currently being rebuilt ↻

#### `backend/src/modules/location/`
**Purpose:** GPS pull via FCM, geofencing, auto-poll when locked
**Files:** `locationService.js` · `locationController.js` · `locationRoutes.js` · `locationScheduler.js` · `schema.sql` · `index.js`
**Endpoints:** `POST /location/:deviceId/pull` · `POST /location/:deviceId/report` · `GET /location/:deviceId/history` · `POST /location/:deviceId/geofence`
**Rules:** Keep last 10 GPS pulls per device · alert dealer if outside geofence while locked · auto-pull every 6h when FULL_LOCK active (Bull queue)
**Score:** 72 (old threshold) ⚠ NEEDS RE-AUDIT

#### `backend/src/modules/admin/`
**Purpose:** Admin dashboard, reseller management, key approvals, audit log
**Files:** `adminService.js` · `adminDeviceService.js` · `adminController.js` · `adminRoutes.js` · `adminMiddleware.js` · `schema.sql` · `index.js`
**Endpoints:** `GET /admin/dashboard` · `GET /admin/resellers` · `POST /admin/resellers/:id/approve` · `POST /admin/resellers/:id/quota` · `GET /admin/devices` · `POST /admin/devices/:id/lock` · `GET /admin/audit-log` · `GET /admin/security-events` · `POST /admin/neir-queue` · `GET /admin/key-requests` · `POST /admin/key-requests/:id/approve`
**Security:** All endpoints require admin JWT + verified 2FA session
**Known issues from last audit:** db.connect() bug (use db.getClient()), lock bypass (must use LockService), triple redundant middleware — being fixed in current rebuild ↻
**Score:** 74 (old threshold) ⚠ BEING REBUILT

#### `backend/src/modules/fraud/`
**Purpose:** Play Integrity webhook, anomaly detection, NEIR/BTRC export
**Files:** `fraudService.js` · `fraudController.js` · `fraudRoutes.js` · `fraudScheduler.js` · `schema.sql` · `index.js`
**Anomaly rules (nightly cron):**
  - Device location jump > 200km in < 2h while locked
  - Multiple IMEIs registered to same NID (except first)
  - Device offline > 30 days in overdue state
  - Dealer with > 50% fraud flag rate
**Endpoints:** `POST /fraud/integrity-report` (Play Integrity webhook) · `POST /fraud/events` · `POST /fraud/resolve/:eventId` · `GET /fraud/neir-export` (Excel, BTRC format)
**Score:** Completed in Phase 2 run — exact score TBD

---

### PHASES 3–5 (NOT STARTED)

| Phase | What gets built |
|-------|----------------|
| Phase 3 | Kotlin User App — DPC client, lock screen overlays, PAUT offline handling, hardware binding |
| Phase 4 | Flutter Dealer App — device enrollment, EMI dashboard, GPS view, lock requests |
| Phase 5 | React Admin Panel — full admin UI, audit log viewer, NEIR queue, reseller management |

---

## 4. SECURITY LAYERS (8-layer model)

```
Layer 1 — Device Owner (DPC)      AMAPI enrolls device as managed, persists through factory reset
Layer 2 — FRP                     Factory Reset Protection via managed Google account — blocks re-use
Layer 3 — Managed Google Account  Google account tied to device, removed only on admin decouple
Layer 4 — Certificate Pinning     Kotlin app pins TLS cert — disabled in dev when API_BASE_URL=localhost
Layer 5 — HSM Command Signing     All lock/unlock/decouple commands signed via KMS before dispatch
Layer 6 — Hardware Binding        Device fingerprint (IMEI+serial+SoC) bound at enrollment — rejects clones
Layer 7 — APK Integrity           Play Integrity API attestation — auto-lock on tampered APK
Layer 8 — Samsung Knox            Additional policy enforcement on Samsung devices
```

**Additional security patterns:**
- All JWT: RS256 (asymmetric) — not HS256
- Activation keys: HMAC-SHA256 signed, burned to IMEI on consumption (one-time)
- Audit log: immutable — database trigger blocks UPDATE and DELETE on audit_log table
- PAUT/PADT: offline-capable signed JWTs for lock/unlock without internet
- 2FA (TOTP): required for all admin actions and device decouple

---

## 5. SERVICE DEPENDENCY GRAPH

```
LockService
  └→ LockCommandService (builds signed command payload)
  └→ LockDeliveryService
        └→ FCM (Channel 1 — FirebaseService)
        └→ AMAPI (Channel 2 — AmapiService)
        └→ PautService / PadtService (Channel 3 — offline token)

DecouplingService
  └→ LockService (for final lock state)
  └→ AmapiService.deleteManagedAccount() (clears FRP)
  └→ NotificationService (dealer notification)
  └→ Bull queue scheduler (5-day countdown)

AdminDeviceService                         ← ⚠ KNOWN BUG: was bypassing LockService directly
  └→ LockService.requestLock()             ← CORRECT path (being fixed in current rebuild)
  └→ LockService.requestUnlock()

EmiService
  └→ DecouplingService.trigger() on final payment

FraudService
  └→ NotificationService (dealer alert)
  └→ SecurityEventRepository
  └→ LockService (auto-lock on integrity failure)
```

---

## 6. ENVIRONMENT VARIABLES

All URLs via env vars — no hardcoded domains (no production domain yet).
```
API_BASE_URL=http://localhost:3000           # Backend API
VITE_API_BASE_URL=http://localhost:3000      # Admin panel (Vite)
POSTGRES_URL=postgresql://...@localhost:5432/emilocker_dev
REDIS_URL=redis://localhost:6379
FIREBASE_PROJECT_ID=REPLACE_WITH_REAL
AMAPI_PROJECT=REPLACE_WITH_REAL
JWT_SECRET=CHANGE_IN_PRODUCTION
HMAC_SECRET=CHANGE_IN_PRODUCTION
NODE_ENV=development
PORT=3000
```

---

## 7. AI ORCHESTRATION

```
┌─────────────────────────────────────────────────────────────────┐
│                     SUPERVISOR CHAIN                            │
│                                                                 │
│  Claude Sonnet (PRIMARY) ──────────────────────────────────┐   │
│    Trigger: Stop hook fires on every Claude reply turn      │   │
│    Responds by writing: CLAUDE_SUPERVISOR_RESPONSE.flag     │   │
│    Timeout: 300s — if no response, routes to fallback       │   │
│                                                             ▼   │
│  Codex ZGBT 5.5 (FALLBACK) — only activates if Claude      │   │
│    is offline for full 300s window                          │   │
└──────────────────────────────────────────────────�────────────┘

Executor:  MIMO V2.5 Pro  (1M context)  — PRD analysis, code review
Worker:    MiniMax M2.7   (256k context) — module implementation, fixes
```

**Build quality standard (as of 2026-05-03):**
- Approval threshold: **score ≥ 95** AND zero HIGH severity issues
- Max fix iterations: **5 per module**
- Fix targets: ALL severity levels (high + medium + low)
- Review scoring: -20 per HIGH, -10 per MEDIUM, -3 per LOW
- Parse failure fallback: **REJECT** (score 0) — never auto-approve

---

## 8. BUILD STATE

```
Phase 1 — Foundation
  ✓ project-structure      (no score — structural)
  ✓ database-schema        (score 82)
  ✓ backend-auth           (score 62) ⚠ pre-strict
  ✓ backend-devices        (score 95) ✓
  ✓ backend-lock-engine    (score 92) ⚠ 3pts below new threshold
  ✓ backend-emi            (score 75) ⚠ pre-strict
  ✓ backend-notifications  (score 82) ⚠ pre-strict
  ✓ backend-server-entry   (score 72) ⚠ pre-strict

Phase 2 — Advanced Backend (strict 95+ standard active from here)
  ✓ backend-keys           (score TBC — completed before strict scoring)
  ✗ backend-decoupling     FAILED — being rebuilt ↻
  ✓ backend-location       (score 72) ⚠ pre-strict
  ✓ backend-admin-api      (score 74) ⚠ being rebuilt ↻
  ✓ backend-fraud          (score TBC)

Phase 3 — Kotlin User App        NOT STARTED
Phase 4 — Flutter Dealer App     NOT STARTED
Phase 5 — React Admin Panel      NOT STARTED
```

**⚠ Re-audit required for Phase 1 + early Phase 2 modules** under the new 95+ scoring standard before any frontend work begins.

---

## 9. MONITOR

- URL: `http://localhost:8080`
- Server: `monitor/server.js` (Node.js + Express + SSE + chokidar)
- Frontend: `monitor/public/index.html` (dark theme, 4-card grid)
- Agent cards: MIMO (blue) · MiniMax (purple) · Claude/PRIMARY (amber) · Codex/FALLBACK (cyan)
- Watches: `build_log.md` · `build_state.json` · file system · `BUILD_COMPLETE.flag`

---

## 10. CRITICAL RULES FOR ALL AI WORKERS

1. **Never hardcode domains** — all URLs from env vars
2. **Never bypass service abstractions** — always use LockService, AuthService, etc. Never call Firebase/AMAPI directly from controllers or admin modules
3. **Audit log is immutable** — never add UPDATE or DELETE on the audit_log table
4. **Certificate pinning** — disable only when `API_BASE_URL` contains `localhost`
5. **All admin endpoints** — require admin JWT + verified 2FA session (single middleware, not stacked)
6. **HMAC signing** — all activation keys must be HMAC-SHA256 signed before storage
7. **db.getClient()** — use this, NOT `db.connect()` or `pool.connect()`
8. **State machines** — never skip states. Transitions must follow the defined order exactly
9. **Score < 95 = not done** — do not mark complete until MIMO gives approved + score ≥ 95
10. **Phase gate** — do NOT start Phase 3 (Kotlin app) until all Phase 2 modules score 95+
