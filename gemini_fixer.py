#!/usr/bin/env python3
"""
EMI Locker — Gemini CLI Module Fixer
======================================
Planner  : Claude Sonnet (identifies issues, writes fix instructions)
Executor : Gemini CLI    (reads instructions, edits files, runs tools)
Reviewer : MIMO V2.5 Pro (re-scores after each fix — must reach 95+)

Usage:
    python gemini_fixer.py                        # fix all under-95 modules
    python gemini_fixer.py --module backend-auth  # fix one specific module
    python gemini_fixer.py --dry-run              # print plans, don't execute
"""

import subprocess, argparse, json, sys
from pathlib import Path
from datetime import datetime

if sys.stdout.encoding != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJECT_DIR  = Path(__file__).parent
GRAPHIFY     = PROJECT_DIR / "GRAPHIFY.md"
STATE_FILE   = PROJECT_DIR / "build_state.json"
LOG_FILE     = PROJECT_DIR / "gemini_fix_run.md"
EXECUTOR_MODEL = "xiaomi-token-plan-singapore/mimo-v2.5-pro"

PASS_SCORE   = 95   # minimum acceptable score
MAX_ROUNDS   = 5    # max Gemini fix rounds per module before escalating to Claude

# ── CLAUDE'S FIX PLANS ────────────────────────────────────────────────────────
# Written by Claude (planner). Each entry is a precise surgical instruction
# for Gemini to execute. Gemini reads GRAPHIFY.md + this plan + the actual files.
# ─────────────────────────────────────────────────────────────────────────────
FIX_PLANS = {

    "database-schema": """
OBJECTIVE: Bring all 10 migration files to production quality (score 95+).

INSPECT: database/migrations/*.sql

FIX EACH FILE:
1. 001_users.sql — Ensure ENUM for role includes exactly: admin, reseller, dealer, customer.
   Add index on email (UNIQUE), phone (UNIQUE), status. Add NOT NULL on all required fields.

2. 002_devices.sql — ENUM for state must include:
   PENDING_ENROLLMENT, ACTIVE, SOFT_LOCK, PARTIAL_LOCK, FULL_LOCK, DECOUPLED, SUSPENDED.
   Add UNIQUE constraint on imei. Add index on dealer_id, customer_id, state.

3. 003_activation_keys.sql — Add CHECK constraint: expires_at > created_at.
   ENUM for status: PENDING_ADMIN, APPROVED, ASSIGNED, CONSUMED, EXPIRED, REVOKED.
   Index on dealer_id, reseller_id, status.

4. 004_emi_schedules.sql — Add CHECK: emi_amount > 0, total_amount > 0, duration_months > 0.
   ENUM for status: ACTIVE, COMPLETED, DEFAULTED, CANCELLED.

5. 005_emi_payments.sql — Add CHECK: amount > 0.
   ENUM for method: bkash, nagad, rocket, card, cash, bank_transfer.
   ENUM for status: PENDING, CONFIRMED, FAILED, REFUNDED. Index on emi_id, device_id.

6. 006_lock_requests.sql — ENUM for reason_code: PAYMENT_OVERDUE, FRAUD_SUSPECTED,
   DEALER_REQUEST, ADMIN_OVERRIDE. ENUM for status: PENDING, APPROVED, REJECTED, EXECUTED.
   Index on device_id, status.

7. 007_decoupling.sql — ENUM for state must match EXACTLY:
   EMI_ACTIVE, FINAL_PAYMENT_RECEIVED, DEALER_NOTIFIED, PENDING_ADMIN_DECOUPLE,
   DEVICE_DECOUPLED, FRAUD_FLAGGED, FRAUD_CONFIRMED, FRAUD_REJECTED.
   Add dealer_notified_at timestamp, fraud_evidence TEXT, rtoc_code VARCHAR(64).

8. 008_audit_log.sql — CRITICAL: Add PostgreSQL trigger that blocks UPDATE and DELETE.
   The trigger must RAISE EXCEPTION 'audit_log is immutable' on any attempt.
   No foreign key on actor_id (actors can be deleted, logs must remain).
   Add index on device_id, actor_id, timestamp.

9. 009_security_events.sql — ENUM for severity: low, medium, high, critical.
   ENUM for event_type: INTEGRITY_FAIL, LOCATION_ANOMALY, NID_DUPLICATE,
   OFFLINE_OVERDUE, DEALER_FRAUD_RATE, VELOCITY_ALERT.
   Add resolved_at timestamp, resolved_by UUID (nullable).

10. 010_paut_tokens.sql — ENUM for action_type: SOFT_UNLOCK, PARTIAL_UNLOCK, FULL_UNLOCK, DECOUPLE.
    Add CHECK: expires_at > authorized_at. Index on device_id, token_hash (UNIQUE), used.

ALSO CHECK: database/seeds/roles.sql has initial admin account seed with bcrypt hash placeholder.
""",

    "backend-auth": """
OBJECTIVE: Fix auth module to score 95+. This is the security gateway — zero tolerance.

INSPECT ALL FILES in backend/src/modules/auth/ and backend/src/middleware/

REQUIRED FIXES:

1. jwt.js — Verify RS256 is used (NOT HS256). If HS256 anywhere, replace with RS256.
   generateAccessToken(payload): 15 min expiry, RS256, includes role + userId.
   generateRefreshToken(payload): 7 day expiry, RS256.
   verifyToken(token): must catch TokenExpiredError and JsonWebTokenError separately.
   Refresh token must be stored in Redis on issue and deleted on logout/refresh rotation.

2. totp.js — Using speakeasy library:
   setup(): generates base32 secret + otpauth URL for QR code. Saves encrypted secret to DB.
   verify(userId, token): validates 6-digit TOTP. Returns true/false.
   generateBackupCodes(): generates 8 one-time backup codes, hashed (bcrypt) and stored in DB.
   verifyBackupCode(userId, code): checks against stored hashes, deletes used code.

3. rateLimit.js — Using express-rate-limit + rate-limit-redis:
   loginLimiter: max 5 attempts per IP per 15 minutes. Returns 429 with Retry-After header.
   Apply loginLimiter ONLY to POST /auth/login and POST /auth/2fa/verify.

4. index.js (routes) — Exact endpoint list:
   POST /auth/login         → validate credentials → issue 2FA challenge (do NOT return JWT yet)
   POST /auth/2fa/verify    → validate TOTP → issue access + refresh JWT pair
   POST /auth/refresh       → verify refresh token from Redis → rotate (delete old, issue new)
   POST /auth/logout        → delete refresh token from Redis, blacklist access token
   POST /auth/2fa/setup     → requireAuth → generate TOTP secret
   POST /auth/2fa/backup    → requireAuth → generate backup codes
   GET  /auth/me            → requireAuth → return user profile

5. middleware/auth.js — requireAuth middleware:
   Extract Bearer token, verify RS256 signature, check Redis blacklist.
   If blacklisted: return 401. If expired: return 401. Attach req.user = decoded payload.

6. middleware/rbac.js — requireRole(role) middleware:
   Check req.user.role === role. Support array: requireRole(['admin', 'reseller']).
   Return 403 with message 'Insufficient permissions' if role mismatch.

VERIFY: No endpoint is reachable without requireAuth where auth is needed.
VERIFY: Passwords are bcrypt with cost factor 12 (not 10, not 14 — exactly 12).
""",

    "backend-lock-engine": """
OBJECTIVE: Close the 3pt gap to reach 95+. Module is at 92 — specific issues only.

INSPECT ALL FILES in backend/src/modules/lock/

REQUIRED FIXES:

1. lockSchedulerService.js — Verify grace period escalation timings are EXACTLY:
   Day 0:   Payment missed → trigger SOFT_LOCK immediately
   Day +7:  Escalate to PARTIAL_LOCK (calls only)
   Day +14: Escalate to FULL_LOCK + flag for admin review
   Use Bull queue delayed jobs (not setTimeout or cron). Each escalation must:
   - Call LockService.requestLock(deviceId, level)
   - Write to audit_log with actor_type='system', action='auto_escalation'

2. lockDeliveryService.js — Verify all 3 channels are tried in sequence with fallback:
   Channel 1: FCM via FirebaseService.sendLockCommand() — if fails, try Channel 2
   Channel 2: AMAPI policy push via AmapiService.applyPolicy() — if fails, try Channel 3
   Channel 3: Issue PAUT token via PautService.issue() — offline resilience
   Log each channel attempt and result to delivery_attempts table or audit_log.
   Never fail silently — always log which channel succeeded or all failed.

3. pautService.js and padtService.js — Verify tokens are:
   - JWT format, signed with HMAC-SHA256 using HMAC_SECRET env var
   - PAUT: 48hr expiry, action_type = SOFT_UNLOCK | PARTIAL_UNLOCK | FULL_UNLOCK
   - PADT: 7 day expiry, action_type = DECOUPLE
   - Stored hash in paut_tokens table (store hash, not raw token)
   - marked used=true on redemption — cannot be reused

4. lockVerificationService.js — After lock command sent, schedule a verification check
   after 60 seconds to confirm device acknowledged. If no ACK: retry Channel 2 or Channel 3.
""",

    "backend-emi": """
OBJECTIVE: Fix EMI engine to score 95+.

INSPECT ALL FILES in backend/src/modules/emi/

REQUIRED FIXES:

1. emiService.js — createSchedule():
   - Validate: total_amount > 0, emi_amount > 0, duration_months 1-60, start_date not in past
   - Calculate: expected monthly due dates array, store as JSONB or separate records
   - Set grace_days default to 7 if not provided (PRD spec)

2. emiService.js — recordPayment():
   - Check for duplicate payment: same device + same month + status CONFIRMED = reject
   - On payment: update current installment status to CONFIRMED
   - Check if this is the final payment (all installments CONFIRMED):
     If yes: call DecouplingService.triggerFinalPayment(deviceId, emiId)
     This MUST happen — final payment must trigger decoupling flow
   - Write to audit_log: action='payment_recorded', details={amount, method, tx_id}

3. emiService.js — getOverdueStatus():
   - Formula: today > (due_date + grace_days) = overdue
   - Return: { daysOverdue: number, graceDaysRemaining: number, status: 'current'|'grace'|'overdue' }

4. emiService.js — requestGracePeriod():
   - Count existing grace period extensions for this device in this EMI cycle
   - If count >= 2: REJECT with error 'Maximum grace period extensions reached'
   - If requested days > 14: REJECT with error 'Grace period cannot exceed 14 days'
   - Otherwise: extend due_date, write to audit_log

5. emiService.js — getUpcoming():
   - Return all devices with EMI due in next 7 days
   - Include device_id, dealer_id, fcm_token, days_until_due
   - Used by the lock scheduler — must be efficient (indexed query on due_date)

6. emiValidation.js — Add input validation for all endpoints using express-validator or joi.
""",

    "backend-notifications": """
OBJECTIVE: Fix notifications module to score 95+.

INSPECT ALL FILES in backend/src/modules/notifications/

REQUIRED FIXES:

1. fcm.service.js — sendToDevice(fcmToken, payload):
   - Use firebase-admin SDK (not REST API directly)
   - On FCM error (UNREGISTERED token): mark device fcm_token as stale in devices table
   - On FCM error (any): return { success: false, error: errorCode }
   - On success: return { success: true, messageId }

2. notification.service.js — sendLockCommand(deviceId, lockLevel):
   - MUST call LockService.requestLock() — do NOT build FCM payload here directly
   - This service coordinates notification, not lock logic
   - sendUnlockCommand(deviceId): same — calls LockService.requestUnlock()

3. notification.service.js — sendReminderNotification(deviceId, daysUntilDue):
   - Payload title: 'EMI Payment Reminder'
   - Payload body: 'Your payment is due in X days. Pay now to avoid service interruption.'
   - daysUntilDue <= 0: body changes to 'Your payment is overdue. Pay immediately.'

4. notification.service.js — sendDealerMessage(deviceId, message):
   - Check dealer-message-rate-limiter BEFORE sending
   - dealer-message-rate-limiter.js: must use Redis. Key = `dealer_msg:${deviceId}:${date}`
   - Increment counter. If > 10: return { blocked: true, reason: 'Daily limit reached' }
   - On send: store in notifications table with delivered/failed status

5. notification.repository.js — trackDelivery(deviceId, type, status, messageId):
   - Insert into notifications table: device_id, type, status, fcm_message_id, sent_at
   - On retry: update existing record, don't insert duplicate

6. sms.service.js — sendSms(phone, message):
   - Use Twilio REST API via twilio npm package
   - Only called for CRITICAL notifications: lock confirmation, unlock confirmation
   - Never called for reminders or dealer messages (FCM only for those)
   - Read TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER from env vars
""",

    "backend-server-entry": """
OBJECTIVE: Fix server entry point to score 95+.

INSPECT: backend/src/index.js and backend/src/config/

REQUIRED FIXES:

1. index.js — Module registration order MUST be:
   1. Load environment config (envValidator.js — fail fast if required vars missing)
   2. Connect PostgreSQL (database.js)
   3. Connect Redis (redis.js)
   4. Apply global middleware: helmet(), cors(), express.json(), morgan()
   5. Register all module routers under /api/v1/
   6. Register error handler LAST (errorHandler.js)
   7. Start Bull queue schedulers (lock, emi, location, decoupling)
   8. Listen on PORT

2. envValidator.js — On startup, validate ALL required env vars exist:
   POSTGRES_URL, REDIS_URL, JWT_SECRET, HMAC_SECRET, FIREBASE_PROJECT_ID,
   AMAPI_PROJECT, PORT, NODE_ENV, CORS_ORIGIN
   If any missing: console.error and process.exit(1) — never start with missing config.

3. config/database.js — Must export: { query, getClient, pool }
   NEVER export a .connect() method — this causes the db.connect() bug.
   getClient(): returns pool.connect() result (a client with release())
   query(text, params): runs pool.query() directly

4. middleware/errorHandler.js — Global error handler:
   - Catch pg errors (code 23505 = unique violation → 409)
   - Catch jwt errors (JsonWebTokenError → 401, TokenExpiredError → 401)
   - Catch validation errors → 400
   - All other errors → 500, log stack trace, never expose stack to client
   - In production (NODE_ENV=production): never send error.message to client for 500s

5. Health check endpoint: GET /health → { status: 'ok', timestamp, db: 'connected', redis: 'connected' }
   Check actual DB and Redis connectivity before returning 200.
""",

    "backend-keys": """
OBJECTIVE: Fix activation key module to score 95+.

INSPECT ALL FILES in backend/src/modules/keys/

REQUIRED FIXES:

1. hmac.service.js — generateKey():
   - Character set: A-Z excluding O, I, S + digits 2-9 excluding 0, 1, 5
   - Format: XXXX-XXXX-XXXX-XXXX (16 chars + 3 dashes)
   - Each key must be signed: HMAC-SHA256(keyValue + dealerId, HMAC_SECRET)
   - Store signature in hmac_sig column

2. keyService.js — requestKeys(resellerId, quantity, justification):
   - Enforce: quantity <= 20% of reseller's monthly_quota
   - If quota exceeded: reject with 'Exceeds 20% single-request limit'
   - Status set to PENDING_ADMIN, write to audit_log

3. keyService.js — approveKeys(requestId, adminId):
   - Verify admin role + 2FA verified session
   - Generate keys via hmac.service.js
   - Set status APPROVED, store in DB, write to audit_log

4. keyService.js — assignKeys(resellerId, dealerId, quantity):
   - Verify available inventory >= quantity
   - Cannot reclaim once assigned — no undo endpoint allowed
   - Write immutable audit_log: reseller_id, dealer_id, quantity, timestamp

5. keyService.js — consumeKey(keyValue, dealerId, deviceId):
   - Validate: HMAC signature matches (re-derive and compare)
   - Validate: key.dealer_id === dealerId (key belongs to this dealer)
   - Validate: key.status === 'APPROVED' or 'ASSIGNED' (not CONSUMED or EXPIRED)
   - Validate: key.expires_at > now (not expired — 72hr window)
   - On success: set status = CONSUMED, device_id = deviceId (PERMANENT — no reversal)
   - Write to audit_log: action='key_consumed', key_id, device_id, dealer_id

6. keyScheduler.js — Cron job every hour:
   - Find all keys where expires_at < now AND status NOT IN (CONSUMED, EXPIRED, REVOKED)
   - Update status to EXPIRED
   - Velocity check: find dealers with >= 10 key consumptions in last 24h
   - If found: create security_event with event_type='VELOCITY_ALERT', severity='high'
""",

    "backend-decoupling": """
OBJECTIVE: Fix decoupling state machine to score 95+. This is the most critical module.

INSPECT ALL FILES in backend/src/modules/decoupling/

REQUIRED FIXES:

1. decouplingService.js — State machine transitions MUST be exact:
   triggerFinalPayment(deviceId, emiId):
     → Set state = FINAL_PAYMENT_RECEIVED
     → Call NotificationService.notifyDealer(deviceId, 'EMI complete — review within 5 days')
     → Schedule Bull job: delay 5 days → auto-notify admin to execute decouple
     → Set state = DEALER_NOTIFIED, record dealer_notified_at = now()
     → Write audit_log

   fraudFlag(deviceId, dealerId, evidence):
     → ONLY allowed if state = DEALER_NOTIFIED
     → Set state = FRAUD_FLAGGED, store evidence TEXT
     → Alert admin via NotificationService
     → Dealer CANNOT block decouple — admin still proceeds regardless
     → Write audit_log

   executeDecouple(deviceId, adminId):
     → Verify adminId has admin role AND verified 2FA session token
     → State must be PENDING_ADMIN_DECOUPLE or FRAUD_FLAGGED (admin overrides fraud flag)
     → Generate RTOC: crypto.randomBytes(32).toString('hex')
     → Set state = PENDING_ADMIN_DECOUPLE
     → Send signed FCM decouple command via LockService (NOT directly via Firebase)
     → Call AmapiService.deleteManagedAccount(deviceId) — this clears FRP
     → On AMAPI success: set state = DEVICE_DECOUPLED, record admin_action_at = now()
     → Write IMMUTABLE audit_log: action='device_decoupled', admin_id, rtoc_code, timestamp
     → If FCM fails: issue PADT token (7 day expiry) instead
     → On PADT: set state = PENDING_ADMIN_DECOUPLE (not DECOUPLED yet — wait for device ack)

2. decouplingScheduler.js — Bull queue jobs:
   5-day countdown job: if 5 days pass after DEALER_NOTIFIED with no fraud flag:
     → Auto-notify admin: 'Device X ready for decouple — no fraud flag received'
     → Set state = PENDING_ADMIN_DECOUPLE

3. decouplingRoutes.js — Endpoints:
   POST /decoupling/:deviceId/fraud-flag  → requireAuth + requireRole('dealer')
   POST /decoupling/:deviceId/execute     → requireAuth + requireRole('admin') + require2FA
   GET  /decoupling/:deviceId/status      → requireAuth + requireRole(['admin','dealer'])

4. CRITICAL — Dealer CANNOT block decouple:
   fraudFlag() must NOT set any flag that prevents executeDecouple().
   Admin executes regardless of fraud flag status.
   Fraud flag only routes the case for admin review, not delay.
""",

    "backend-location": """
OBJECTIVE: Fix location module to score 95+.

INSPECT ALL FILES in backend/src/modules/location/

REQUIRED FIXES:

1. locationService.js — pullGPS(deviceId, requestedBy):
   - Send FCM command to device requesting GPS report within 60 seconds
   - FCM payload: { type: 'GPS_PULL_REQUEST', requestId: uuid, timeout: 60 }
   - Store pending pull request in Redis with 60s TTL: key = `gps_pull:${deviceId}`
   - Return { requestId, status: 'pending' }

2. locationService.js — reportGPS(deviceId, { latitude, longitude, accuracy, battery_level }):
   - Validate: latitude -90 to 90, longitude -180 to 180, accuracy > 0
   - Store in location_history table
   - Enforce 10-record limit: DELETE oldest if count > 10 for this deviceId
   - Check geofence: if device has active geofence AND device is locked:
     calculate distance from geofence center using Haversine formula
     if outside boundary: create security_event + notify dealer
   - Clear Redis pending pull: DEL `gps_pull:${deviceId}`

3. locationService.js — setGeofence(deviceId, { centerLat, centerLng, radiusKm, cityName }):
   - Validate: radiusKm between 1 and 500
   - Upsert into location_geofences table (one geofence per device)
   - Write to audit_log

4. locationScheduler.js — Auto-pull on FULL_LOCK:
   - Subscribe to lock state change events (or poll devices table)
   - When device enters FULL_LOCK: schedule recurring Bull job every 6 hours
   - Job calls pullGPS(deviceId, 'system')
   - When device leaves FULL_LOCK: cancel/remove the recurring job
   - Never schedule duplicate jobs for same device (check existing jobs first)

5. schema.sql — location_history table must have index on (device_id, created_at DESC).
   location_geofences table: unique index on device_id (one geofence per device).
""",

    "backend-admin-api": """
OBJECTIVE: Fix admin API to score 95+. Three known critical bugs from audit.

INSPECT ALL FILES in backend/src/modules/admin/

FIX 1 — db.connect() runtime crash (HIGH severity):
   Open adminService.js and adminDeviceService.js.
   Find ALL occurrences of: db.connect() or pool.connect() or db.pool.connect()
   Replace with: db.getClient()
   The database module exports { query, getClient, pool }.
   There is NO .connect() method. This causes immediate runtime crash.

FIX 2 — Lock bypass — phantom locks (HIGH severity):
   Open adminDeviceService.js.
   Find lockDevice() and unlockDevice() methods.
   Remove ALL direct calls to:
     - firebaseService.send() or firebaseService.sendCommand()
     - commandSigningService.sign()
     - amapiService.applyPolicy()
   Replace with:
     lockDevice(deviceId, level, adminId):
       return await lockService.requestLock(deviceId, level, { requestedBy: adminId, role: 'admin' })
     unlockDevice(deviceId, adminId):
       return await lockService.requestUnlock(deviceId, { requestedBy: adminId, role: 'admin' })
   Import lockService at top of file. Remove unused imports for firebase/command/amapi services.

FIX 3 — Triple redundant middleware (MEDIUM severity):
   Open adminRoutes.js.
   For each route, use EXACTLY this middleware stack and nothing else:
     router.use(requireAuth)          ← applied once at router level
     router.use(requireRole('admin')) ← applied once at router level
     router.use(require2FA)           ← applied once at router level
   Remove any per-route repetition of requireRole, verifyAdminRole, requireVerified2FA.
   These three applied at router level cover all routes — no need to repeat per-route.

FIX 4 — Dashboard stats query (MEDIUM severity):
   adminService.js — getDashboard():
   Must return: { totalDevices, overdueCount, lockedCount, decouplingPending }
   Use single efficient query with COUNT + CASE WHEN, not 4 separate queries.

FIX 5 — Audit log endpoint (MEDIUM severity):
   GET /admin/audit-log must support query params: ?deviceId=&actorId=&action=&page=&limit=
   Use parameterized query with dynamic WHERE clauses.
   Default limit: 50, max limit: 200.
   Return: { data: [...], total, page, limit }
""",

    "backend-fraud": """
OBJECTIVE: Fix fraud module to score 95+.

INSPECT ALL FILES in backend/src/modules/fraud/

REQUIRED FIXES:

1. fraudService.js — handleIntegrityReport(deviceId, attestationResult):
   - Called by POST /fraud/integrity-report (Play Integrity API webhook)
   - If attestationResult.appIntegrity.appRecognitionVerdict !== 'PLAY_RECOGNIZED':
     → Call LockService.requestLock(deviceId, 'FULL_LOCK')
     → Create security_event: type='INTEGRITY_FAIL', severity='critical'
     → Notify dealer via NotificationService
   - Verify webhook signature using Google public key (reject unsigned webhooks)

2. fraudScheduler.js — Nightly cron (run at 02:00 local time), 4 anomaly rules:

   Rule 1 — Location jump:
   SELECT devices with 2+ location records < 2 hours apart where distance > 200km AND device is locked.
   Use Haversine formula in SQL or JS. Create security_event type='LOCATION_ANOMALY'.

   Rule 2 — NID duplication:
   SELECT nid values that appear on more than 1 customer record.
   For each duplicate NID: flag all devices after the first registration.
   Create security_event type='NID_DUPLICATE', severity='high'.

   Rule 3 — Offline overdue:
   SELECT devices where last_heartbeat < (now - 30 days) AND emi status = overdue.
   Create security_event type='OFFLINE_OVERDUE', severity='medium'.

   Rule 4 — Dealer fraud rate:
   SELECT dealers where (COUNT fraud_flags / COUNT devices) > 0.5 AND COUNT devices >= 5.
   Create security_event type='DEALER_FRAUD_RATE', severity='high'.

3. fraudService.js — generateNeirExport():
   - Excel format (.xlsx) using exceljs library
   - Columns required by BTRC: IMEI, Device Model, Dealer Name, Dealer NID, Date Flagged, Reason
   - Return buffer for download
   - Endpoint: GET /fraud/neir-export → res.setHeader('Content-Disposition', 'attachment; filename=neir-export.xlsx')

4. fraudRoutes.js:
   POST /fraud/integrity-report → public (no auth — called by Google webhook)
   POST /fraud/events           → requireAuth + requireRole(['admin','dealer'])
   POST /fraud/resolve/:eventId → requireAuth + requireRole('admin') + require2FA
   GET  /fraud/neir-export      → requireAuth + requireRole('admin')
""",
}

# ── HELPERS ───────────────────────────────────────────────────────────────────

def log(msg: str):
    ts  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")

def load_graphify() -> str:
    if GRAPHIFY.exists():
        return GRAPHIFY.read_text(encoding="utf-8")[:6000]
    return "[GRAPHIFY not found]"

def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception:
        return {"completed": [], "failed": []}

def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")

def run_gemini(prompt: str, timeout: int = 600) -> tuple[bool, str]:
    """Run Gemini CLI in yolo headless mode with the given prompt via stdin.

    Why stdin: gemini is a .cmd file on Windows (needs shell=True), and embedding
    a multi-thousand-character prompt as a CLI argument causes quoting failures.
    Gemini docs: -p prompt is appended to stdin input, so stdin carries the full
    context and -p triggers headless/non-interactive mode.
    """
    try:
        # Note: --allowed-mcp-server-names "" causes a PolicyEngine crash in Gemini CLI
        # ("mcpName is required if specified"). Remove the flag — yolo mode handles MCP fine.
        result = subprocess.run(
            'gemini --skip-trust --yolo -p "Follow the instructions from stdin exactly."',
            input=prompt,
            capture_output=True, text=True,
            encoding="utf-8", errors="replace",
            timeout=timeout,
            cwd=str(PROJECT_DIR),
            shell=True,
        )
        output = (result.stdout + result.stderr).strip()
        # Strip MCP noise lines
        clean_lines = [
            l for l in output.splitlines()
            if not any(l.lower().startswith(p) for p in [
                "mcp issues", "ripgrep is not available", "trust check",
                "using model", "gemini cli", "✓", "✗", "⠋", "⠙",
            ])
        ]
        return result.returncode == 0, "\n".join(clean_lines)
    except subprocess.TimeoutExpired:
        return False, f"Gemini timeout after {timeout}s"
    except Exception as e:
        return False, f"Gemini error: {e}"

def run_mimo_review(module_name: str, summary: str) -> dict:
    """Ask MIMO to review the fixed module. Returns score dict.

    Uses string command + shell=True (Windows .cmd file), prompt via stdin.
    List + shell=True breaks on Windows — always use a string here.
    """
    prd_summary_file = PROJECT_DIR / "prd_summary.md"
    prd_ref = prd_summary_file.read_text(encoding="utf-8")[:5000] if prd_summary_file.exists() else ""

    prompt = (
        f"You are the EXECUTOR AI reviewing module: {module_name}\n"
        "This is a SECURITY-CRITICAL Android MDM app. Score strictly.\n\n"
        f"Implementation summary:\n{summary[:3000]}\n\n"
        "Score rubric: start at 100. Deduct -20 per HIGH issue, -10 per MEDIUM, -3 per LOW.\n"
        "Only return status=approved if score >= 95 AND zero HIGH issues.\n\n"
        "IMPORTANT: Output ONLY valid JSON — no markdown code fences, no text before or after.\n"
        "The response must start with '{' and end with '}'.\n\n"
        '{"status": "approved|needs_changes", "score": 0-100, '
        '"issues": [{"severity": "high|medium|low", "description": "...", "fix": "..."}]}\n\n'
        f"PRD REFERENCE:\n{prd_ref}"
    )
    try:
        cmd = f'opencode run -m "{EXECUTOR_MODEL}"'
        result = subprocess.run(
            cmd,
            input=prompt, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=480,
            cwd=str(PROJECT_DIR), shell=True,
        )
        out = result.stdout + result.stderr
        # Strip markdown code fences if present
        cleaned = out.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("```", 2).get(1, cleaned).strip()
        if cleaned.startswith("json"):
            cleaned = cleaned[4:].strip()
        # Find JSON object boundaries
        start = cleaned.find("{")
        end = cleaned.rfind("}") + 1
        if start != -1 and end > start:
            json_str = cleaned[start:end]
            parsed = json.loads(json_str)
            if "score" in parsed:
                return parsed
        log(f"[{module_name}] MIMO review output could not be parsed — raw: {out[:300]}")
    except json.JSONDecodeError as e:
        log(f"[{module_name}] MIMO JSON decode error: {e}")
    except Exception as e:
        log(f"[{module_name}] MIMO review exception: {e}")
    return {"status": "needs_changes", "score": 0, "issues": [
        {"severity": "high", "description": "MIMO review parse failed — output not valid JSON", "fix": "Re-inspect module manually"}
    ]}

def run_codex(module_name: str, plan: str, graphify: str) -> str | None:
    """Run Codex as second-tier fixer when Gemini exhausts its rounds."""
    log(f"[{module_name}] Codex: executing fix...")
    prompt = (
        f"You are Codex ZGBT 5.5, the SECONDARY CODE FIXER for the EMI Locker Platform.\n"
        f"Project root: {PROJECT_DIR}\n\n"
        "=== SYSTEM CONTEXT (GRAPHIFY) ===\n"
        f"{graphify}\n\n"
        "=== YOUR TASK ===\n"
        f"Fix module: {module_name}\n\n"
        "=== FIX INSTRUCTIONS ===\n"
        f"{plan}\n\n"
        "=== RULES ===\n"
        "1. Read current files before changing anything\n"
        "2. Apply every fix listed — no placeholders, fully implemented\n"
        "3. Only touch files in this module — no other modules\n"
        "4. Output a summary of all changes made\n"
    )
    try:
        result = subprocess.run(
            'codex exec -m "gpt-5.4" --skip-git-repo-check --sandbox danger-full-access -',
            input=prompt,
            capture_output=True, text=True,
            encoding="utf-8", errors="replace",
            timeout=600,
            cwd=str(PROJECT_DIR),
            shell=True,
        )
        output = (result.stdout + result.stderr).strip()
        if result.returncode == 0 and output:
            log(f"[{module_name}] Codex exit=OK")
            return output
        log(f"[{module_name}] Codex exit=FAIL (rc={result.returncode}): {output[:300]}", )
    except subprocess.TimeoutExpired:
        log(f"[{module_name}] Codex timeout after 600s")
    except Exception as e:
        log(f"[{module_name}] Codex error: {e}")
    return None

# ── CORE FIX LOOP ─────────────────────────────────────────────────────────────

def fix_module(module_name: str, dry_run: bool = False) -> bool:
    plan = FIX_PLANS.get(module_name)
    if not plan:
        log(f"[{module_name}] No fix plan defined by Claude — skipping.")
        return False

    graphify = load_graphify()
    log(f"\n{'='*60}")
    log(f"GEMINI FIXER: {module_name}")
    log(f"{'='*60}")

    if dry_run:
        log(f"[DRY RUN] Plan for {module_name}:\n{plan}")
        return True

    for attempt in range(1, MAX_ROUNDS + 1):
        log(f"[{module_name}] Round {attempt}/{MAX_ROUNDS} — Gemini executing fix...")

        full_prompt = (
            f"You are Gemini, the CODE EXECUTOR for the EMI Locker Platform.\n"
            f"Project root: {PROJECT_DIR}\n\n"
            "=== SYSTEM CONTEXT (GRAPHIFY) ===\n"
            f"{graphify}\n\n"
            "=== YOUR TASK ===\n"
            f"Fix the module: {module_name}\n\n"
            "=== CLAUDE'S FIX INSTRUCTIONS ===\n"
            f"{plan}\n\n"
            "=== EXECUTION RULES ===\n"
            "1. Read the actual current files first before changing anything\n"
            "2. Apply EVERY fix listed above — do not skip any\n"
            "3. Write the fixed files back to disk\n"
            "4. Do not change other modules — only the files listed above\n"
            "5. Do not add placeholder comments like '// TODO' — implement fully\n"
            "6. After all fixes: output a brief summary of what you changed\n"
        )

        success, output = run_gemini(full_prompt, timeout=600)
        log(f"[{module_name}] Gemini exit={'OK' if success else 'FAIL'}")
        if output:
            log(f"[{module_name}] Gemini output (truncated):\n{output[:800]}")

        # MIMO re-review
        log(f"[{module_name}] MIMO reviewing fixed code...")
        review = run_mimo_review(module_name, output or "No output from Gemini")
        score  = review.get("score", 0)
        status = review.get("status", "needs_changes")
        issues = review.get("issues", [])
        highs  = [i for i in issues if i.get("severity") == "high"]

        log(f"[{module_name}] MIMO score={score} status={status} high_issues={len(highs)}")

        if status == "approved" and score >= PASS_SCORE and len(highs) == 0:
            log(f"[{module_name}] PASSED {score}/100 — updating build state")
            state = load_state()
            if module_name not in state.get("completed", []):
                state.setdefault("completed", []).append(module_name)
            if module_name in state.get("failed", []):
                state["failed"].remove(module_name)
            save_state(state)
            return True

        # Inject MIMO's issues into next Gemini round
        if issues:
            issue_text = "\n".join(
                f"  [{i.get('severity','?').upper()}] {i.get('description','')} → {i.get('fix','')}"
                for i in issues
            )
            plan = (
                f"Previous attempt scored {score}/100. Still failing.\n"
                f"MIMO reviewer found these remaining issues — fix ALL of them:\n{issue_text}\n\n"
                f"Original instructions (still apply):\n{FIX_PLANS[module_name]}"
            )
        log(f"[{module_name}] Round {attempt} incomplete — continuing...")

    # ── Gemini exhausted — try Codex as second fixer ──────────────────────────
    log(f"[{module_name}] Gemini exhausted {MAX_ROUNDS} rounds — routing to Codex (second fixer).")
    codex_result = run_codex(module_name, plan, graphify)
    if codex_result:
        review = run_mimo_review(module_name, codex_result)
        score  = review.get("score", 0)
        status = review.get("status", "needs_changes")
        highs  = [i for i in review.get("issues", []) if i.get("severity") == "high"]
        log(f"[{module_name}] Codex fix — MIMO score={score} status={status} high_issues={len(highs)}")
        if status == "approved" and score >= PASS_SCORE and len(highs) == 0:
            log(f"[{module_name}] PASSED via Codex {score}/100 — updating build state")
            state = load_state()
            if module_name not in state.get("completed", []):
                state.setdefault("completed", []).append(module_name)
            if module_name in state.get("failed", []):
                state["failed"].remove(module_name)
            save_state(state)
            return True

    # ── Codex also failed — escalate to Claude (heavy lifter) ─────────────────
    log(f"[{module_name}] Codex could not resolve. ESCALATING TO CLAUDE — human-level review required.")
    log(f"[{module_name}] Claude: inspect this module manually and provide a new fix plan.")
    state = load_state()
    state.setdefault("failed", [])
    if module_name not in state["failed"]:
        state["failed"].append(module_name)
    save_state(state)
    return False

# ── MAIN ──────────────────────────────────────────────────────────────────────

UNDER_95_MODULES = [
    "database-schema",       # 82
    "backend-auth",          # 62  ← most critical
    "backend-lock-engine",   # 92  ← closest to passing
    "backend-emi",           # 75
    "backend-notifications", # 82
    "backend-server-entry",  # 72
    "backend-keys",          # TBC
    "backend-decoupling",    # 75
    "backend-location",      # 72
    "backend-admin-api",     # 78  ← known bugs documented
    "backend-fraud",         # 75
]

def main():
    parser = argparse.ArgumentParser(description="Gemini CLI Module Fixer — planned by Claude")
    parser.add_argument("--module",  type=str, help="Fix a single specific module")
    parser.add_argument("--dry-run", action="store_true", help="Print plans only, no execution")
    args = parser.parse_args()

    log("=" * 60)
    log("EMI LOCKER — GEMINI FIXER")
    log("Planner: Claude Sonnet | Executor: Gemini CLI | Reviewer: MIMO")
    log("Target: All modules must score 95+")
    log("=" * 60)

    modules = [args.module] if args.module else UNDER_95_MODULES

    passed, failed_list = [], []
    for mod in modules:
        ok = fix_module(mod, dry_run=args.dry_run)
        (passed if ok else failed_list).append(mod)

    log("\n" + "=" * 60)
    log(f"GEMINI FIXER COMPLETE")
    log(f"  Passed  : {len(passed)}  — {passed}")
    log(f"  Failed  : {len(failed_list)}  — {failed_list}")
    if failed_list:
        log("  ESCALATE to Claude for manual review of failed modules.")
    log("=" * 60)

if __name__ == "__main__":
    main()
