#!/usr/bin/env python3
"""
EMI Locker Autonomous Builder — v2.0
=====================================
Three-role AI orchestration:

  Supervisor : Gemini 2.5 Pro (via OpenCode) — audits checkpoints, validates against PRD
  Executor   : MiniMax-M2.7  (via OpenCode)  — complex planning + review (harder tasks)
  Worker     : MiniMax-M2.5  (via OpenCode)  — module implementation + fixes (lighter tasks)

Note: Claude has been removed — API rate limit exceeded.

Usage:
    python autonomous_builder.py                        # full auto, all phases
    python autonomous_builder.py --phase 1              # only Phase 1
    python autonomous_builder.py --start-module auth    # resume from a specific module
"""

import subprocess
import argparse
import json
import os
import sys
import time
import shutil
from pathlib import Path
from datetime import datetime
import threading
from concurrent.futures import ThreadPoolExecutor

# Force UTF-8 output on Windows (fixes cp1252 UnicodeEncodeError)
if sys.stdout.encoding != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr.encoding != "utf-8":
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# ── Dual-Mode Skill Packs ──────────────────────────────────────────────────────
PROTOTYPE_SKILLS = """
PROTOTYPE MODE ACTIVE:
- Prioritize speed over elegance.
- Use the simplest working pattern.
- Skip optional security layers (no HMAC signing, no strict cert pinning required).
- Add TODO comments for production upgrade points.
"""

PRODUCTION_SKILLS = """
PRODUCTION GRADE MODE ACTIVE:
- Every external call must have retry + timeout.
- Every error must be typed and handled.
- Use Repository + Service pattern strictly.
- HMAC-SHA256 command signing is MANDATORY on all mutations.
- Certificate Pinning is MANDATORY on all external requests.
- All sensitive operations must write to audit_logs table.
"""

# ── Model IDs ──────────────────────────────────────────────────────────────────
# Executor: Gemini CLI in --yolo mode (headless, no permission prompts)
GEMINI_EXECUTOR        = "gemini-cli-yolo"

# Worker 1: MiniMax M2.7 via OpenCode (primary)
WORKER_MODEL_1         = "minimax-coding-plan/MiniMax-M2.7"

# Worker 2: MiniMax M2.7 (shifted from Gemma due to exhaustion)
WORKER_MODEL_2         = "minimax-coding-plan/MiniMax-M2.7"

# Legacy aliases (used by fallback/review paths)
EXECUTOR_MODEL         = "google/gemini-2.5-pro"
WORKER_MODEL           = WORKER_MODEL_1
MINIMAX_EXECUTOR_MODEL = WORKER_MODEL_1
MINIMAX_WORKER_MODEL   = WORKER_MODEL_1

# Supervisor: Claude (primary — this context window)
PRIMARY_SUPERVISOR      = "Claude"
PRIMARY_SUPERVISOR_FLAG = "CLAUDE_SUPERVISOR_RESPONSE.flag"

SUPERVISOR_NAME  = "Codex"                            # secondary fallback — DO NOT CHANGE
SUPERVISOR_CLI   = "codex_cli.py"
SUPERVISOR_MODEL = "gpt-5.4"

# ── Development URLs (no real domain yet) ──────────────────────────────────────
# All generated code must use environment variables for URLs.
# These are the DEFAULT values written into .env.example and config files.
# When a real domain is obtained, only the .env file needs updating — no code changes.
DEV_URLS = {
    "api":         "http://localhost:3000",       # Node.js backend API
    "admin":       "http://localhost:5173",       # React admin panel (Vite dev server)
    "dealer_app":  "http://localhost:3000",       # Flutter app points to same API
    "firebase":    "REPLACE_WITH_FIREBASE_PROJECT_ID",
    "amapi":       "https://androidmanagement.googleapis.com/v1",  # Google's URL — fixed
}

# Instruction injected into every prompt so models never hardcode domains
DEV_URL_INSTRUCTION = """
IMPORTANT — NO HARDCODED DOMAINS:
This project has no production domain yet. Follow these rules strictly:
1. ALL URLs must come from environment variables — never hardcode any domain
2. Backend API base URL env var: API_BASE_URL (default: http://localhost:3000)
3. Admin panel API env var: VITE_API_BASE_URL (default: http://localhost:3000)
4. Flutter app API env var: read from .env file via flutter_dotenv, key: API_BASE_URL
5. Kotlin app API env var: read from BuildConfig, key: API_BASE_URL
6. Certificate pinning in dev: DISABLE pinning when API_BASE_URL contains 'localhost'
   (add isDev check: if (BuildConfig.API_BASE_URL.contains("localhost")) skip pinning)
7. In .env.example, document every URL variable with a comment: # Replace with real domain before deploy
8. Do NOT reference api.emilocker.com, admin.emilocker.com, or any .com domain anywhere in code
"""

# ── Timeouts ───────────────────────────────────────────────────────────────────
TIMEOUT_PLAN             = 600   # 10 min — executor reads full PRD, creates plan
TIMEOUT_BUILD            = 900   # 15 min — worker implements a module (increased for Flutter)
TIMEOUT_REVIEW           = 480   #  8 min — executor reviews implementation
CLAUDE_SUPERVISOR_TIMEOUT = 600  # 10 min — kept for the Gemini terminal polling window
TIMEOUT_FIX    = 720   # 12 min — worker applies fixes (increased for complex modules)

# ── Module Definitions ─────────────────────────────────────────────────────────
# model: "executor" (MIMO 1M) for large cross-file work
#        "worker"   (MINIMAX 256k) for scoped single-module work
MODULES = [
    # ── Phase 1: Foundation ──────────────────────────────────────────────────
    {
        "name": "project-structure",
        "phase": 1,
        "model": "worker",
        "description": (
            "Create the top-level project directory structure:\n"
            "  /backend      — Node.js + Express API\n"
            "  /user-app     — Kotlin Android app\n"
            "  /dealer-app   — Flutter app (dealer + reseller roles)\n"
            "  /admin-panel  — React web app\n"
            "  /database     — PostgreSQL migrations\n"
            "  /firebase     — Firebase config and rules\n"
            "Create package.json for backend, pubspec.yaml for Flutter, "
            "build.gradle for Kotlin app, package.json for admin panel. "
            "Include .gitignore and README.md for each sub-project."
        ),
    },
    {
        "name": "database-schema",
        "phase": 1,
        "model": "executor",
        "description": (
            "Create the full PostgreSQL schema as migration files in /database/migrations/.\n"
            "Tables required (all sensitive fields encrypted at rest with AES-256 notation in comments):\n"
            "  001_users.sql        — id, email, phone, role(admin/reseller/dealer/customer), "
            "password_hash, totp_secret, status, created_at\n"
            "  002_devices.sql      — id, imei, serial, soc_model, customer_id, dealer_id, "
            "state(ENUM), amapi_device_id, fcm_token, enrolled_at\n"
            "  003_activation_keys.sql — id, key_value(HMAC-SHA256 signed), reseller_id, "
            "dealer_id, device_id, status(ENUM), expires_at, hmac_sig\n"
            "  004_emi_schedules.sql — id, device_id, total_amount, emi_amount, duration_months, "
            "start_date, grace_days, status\n"
            "  005_emi_payments.sql  — id, emi_id, device_id, amount, payment_date, method, "
            "tx_id, status\n"
            "  006_lock_requests.sql — id, device_id, dealer_id, reason_code(ENUM), note, "
            "status, server_verdict, verdict_reason, created_at\n"
            "  007_decoupling.sql    — id, device_id, emi_id, state(ENUM), dealer_notified_at, "
            "fraud_flag, admin_action_at, rtoc_code\n"
            "  008_audit_log.sql     — id, actor_id, actor_type, device_id, action, details_json, "
            "ip, timestamp — NO UPDATE OR DELETE ALLOWED (trigger enforced)\n"
            "  009_security_events.sql — id, device_id, event_type, severity, details_json, resolved\n"
            "  010_paut_tokens.sql   — id, device_id, token_hash, action_type, authorized_at, "
            "expires_at, used\n"
            "Also create /database/seeds/roles.sql with initial admin account seed. "
            "Add proper indexes, foreign keys, and ENUMs for all state machine fields."
        ),
    },
    {
        "name": "backend-auth",
        "phase": 1,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/auth/ with:\n"
            "  - JWT generation and verification middleware (RS256, 15 min access token, "
            "7 day refresh token)\n"
            "  - TOTP 2FA using speakeasy library (setup, verify, backup codes)\n"
            "  - RBAC middleware — roles: admin, reseller, dealer, customer\n"
            "  - Login endpoint POST /auth/login — returns JWT + requires 2FA on second step\n"
            "  - Refresh endpoint POST /auth/refresh\n"
            "  - Logout endpoint POST /auth/logout (blacklist token)\n"
            "  - Rate limiting: max 5 login attempts per IP per 15 minutes\n"
            "  - All passwords hashed with bcrypt cost 12\n"
            "  - Session stored in Redis (use ioredis)\n"
            "Create /backend/src/middleware/auth.js and /backend/src/middleware/rbac.js"
        ),
    },
    {
        "name": "backend-devices",
        "phase": 1,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/devices/ with:\n"
            "  - AMAPI integration: Google Android Management API v1 client setup\n"
            "  - POST /devices/enroll — validate enrollment token, record IMEI+serial+SoC, "
            "create AMAPI device entry, bind managed Google account, store amapi_device_id\n"
            "  - GET /devices/:id — device info with current state\n"
            "  - POST /devices/:id/policy — push Device Owner policies via AMAPI:\n"
            "    setGlobalSetting ADB_ENABLED=0, DEVELOPMENT_SETTINGS_ENABLED=0,\n"
            "    setUsbDataSignalingEnabled=false, setSecureSetting INSTALL_NON_MARKET_APPS=0\n"
            "  - POST /devices/:id/fcm-token — update FCM token\n"
            "  - GET /devices/:id/status — current lock state from Firebase RT DB\n"
            "  - Firebase Realtime DB integration: write to devices/{deviceId}/status on state change\n"
            "Include hardware binding: store IMEI + serial + SoC hash, verify on every command."
        ),
    },
    {
        "name": "backend-lock-engine",
        "phase": 1,
        "model": "executor",
        "description": (
            "Create /backend/src/modules/lock/ — the Server Verification Engine:\n\n"
            "POST /lock/request — Dealer submits lock request:\n"
            "  Validation rules (REJECT if any are true):\n"
            "    1. EMI payment is NOT overdue (payment current or within grace period)\n"
            "    2. Grace period extension is active\n"
            "    3. Device already at requested or higher lock level\n"
            "    4. Dealer submitted 3+ invalid requests in last 24 hours\n"
            "    5. Device last GPS location is at dealer's registered shop address\n"
            "    6. Reason is SUSPECTED_FRAUD or SUSPECTED_SALE (escalate to admin)\n"
            "  If VALID: schedule lock, send FCM command to device, return APPROVED\n"
            "  If INVALID: return REJECTED with specific reason — do NOT lock device\n\n"
            "POST /lock/command — internal: generate signed lock command\n"
            "  Command payload: {deviceImei, timestamp, nonce, actionType, hmacSignature}\n"
            "  Sign with HMAC-SHA256 using server secret key\n"
            "  Command expires in 5 minutes. Used nonces stored in Redis and rejected.\n\n"
            "Auto-lock scheduler (node-cron): runs daily at midnight\n"
            "  Day -7: send reminder push notification\n"
            "  Day -3: send warning overlay push\n"
            "  Day 0:  send overdue alert overlay\n"
            "  Day +1: apply REMINDER_MODE lock\n"
            "  Day +3: apply PARTIAL_LOCK\n"
            "  Day +7: apply FULL_LOCK\n"
            "  Day +14: apply FULL_LOCK + flag for admin review\n\n"
            "Three-channel delivery:\n"
            "  Channel 1: FCM push (primary)\n"
            "  Channel 2: AMAPI policy push (secondary — bypasses FCM)\n"
            "  Channel 3: PAUT token issued to device for offline unlock\n\n"
            "POST /lock/paut — issue Pre-Authorized Unlock Token (JWT, signed, 48hr expiry)\n"
            "POST /lock/padt — issue Pre-Authorized Decouple Token (JWT, signed, 7 day expiry)"
        ),
    },
    {
        "name": "backend-emi",
        "phase": 1,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/emi/ with:\n"
            "  - POST /emi/schedule — create EMI schedule for a device\n"
            "  - GET /emi/:deviceId — get full schedule with payment status per installment\n"
            "  - POST /emi/:deviceId/payment — record a payment (amount, method, tx_id)\n"
            "  - GET /emi/:deviceId/overdue-status — returns days overdue (0 if current)\n"
            "  - POST /emi/:deviceId/grace-period — dealer requests grace period extension "
            "(max 14 days, max 2 per device per EMI cycle, server enforces)\n"
            "  - GET /emi/upcoming — all devices with EMI due in next 7 days (for scheduler)\n"
            "  - Overdue detection: compare today vs due_date + grace_days\n"
            "  - Final payment detection: triggers decoupling state machine"
        ),
    },
    {
        "name": "backend-notifications",
        "phase": 1,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/notifications/ with:\n"
            "  - FCM integration using firebase-admin SDK\n"
            "  - sendToDevice(fcmToken, payload) — send push to specific device\n"
            "  - sendLockCommand(deviceId, lockLevel) — sends signed lock command via FCM\n"
            "  - sendUnlockCommand(deviceId) — sends signed unlock command via FCM\n"
            "  - sendReminderNotification(deviceId, daysUntilDue) — payment reminder\n"
            "  - sendDealerMessage(deviceId, message) — custom dealer overlay message "
            "(max 10 per device per day, enforced in Redis)\n"
            "  - POST /notifications/message — dealer sends custom message to device\n"
            "  - FCM delivery tracking: store delivered/failed status in PostgreSQL\n"
            "  - SMS fallback via Twilio for critical notifications (lock/unlock confirmations)"
        ),
    },
    {
        "name": "backend-keys",
        "phase": 2,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/keys/ with:\n"
            "  - Key generation: format XXXX-XXXX-XXXX-XXXX\n"
            "    Character set: A-Z (excl O, I, S) + 2-9 (excl 0, 1, 5) = ~77 bits entropy\n"
            "    Each key signed with HMAC-SHA256, encoded with dealer ID\n"
            "  - POST /keys/request — reseller requests keys (quantity + justification)\n"
            "    Enforce: max 20% of monthly quota per single request\n"
            "    Status set to PENDING_ADMIN\n"
            "  - POST /keys/approve/:requestId — admin approves, server generates keys via HSM\n"
            "  - POST /keys/assign — reseller assigns keys to dealer inventory\n"
            "    Enforce: cannot exceed available inventory, cannot reclaim once assigned\n"
            "    Full audit log: reseller_id, dealer_id, quantity, timestamp (immutable)\n"
            "  - POST /keys/consume — dealer uses key during enrollment\n"
            "    Validate: key matches dealer ID, key not expired (72hr), key not already used\n"
            "    On success: burn key to IMEI permanently, status = CONSUMED\n"
            "  - Cron job: expire keys unused for 72 hours\n"
            "  - Velocity check: dealer using 10+ keys in 24h triggers admin alert"
        ),
    },
    {
        "name": "backend-decoupling",
        "phase": 2,
        "model": "executor",
        "description": (
            "Create /backend/src/modules/decoupling/ — the full decoupling state machine:\n\n"
            "States: EMI_ACTIVE → FINAL_PAYMENT_RECEIVED → DEALER_NOTIFIED → "
            "PENDING_ADMIN_DECOUPLE → DEVICE_DECOUPLED\n"
            "  (or FRAUD_FLAGGED → FRAUD_CONFIRMED/FRAUD_REJECTED branches)\n\n"
            "Triggers:\n"
            "  - On final payment: automatically transition to FINAL_PAYMENT_RECEIVED\n"
            "  - Notify dealer in-app: 'Device X has completed EMI. Review within 5 days'\n"
            "  - Start 5-day countdown timer (use Bull queue with delay)\n"
            "  - POST /decoupling/:deviceId/fraud-flag — dealer flags fraud with evidence\n"
            "    Dealer CAN: flag with written evidence\n"
            "    Dealer CANNOT: block or delay decoupling\n"
            "  - POST /decoupling/:deviceId/execute — ADMIN ONLY, requires 2FA\n"
            "    Generate RTOC (Release Token One-time Code)\n"
            "    Send signed Decouple Command via FCM\n"
            "    On success: call AMAPI to delete managed account (clears FRP)\n"
            "    Mark device DECOUPLED in DB — immutable audit log entry\n"
            "  - If FCM fails: issue PADT (7 day expiry), device checks on reconnect\n"
            "  - After 5 days with no fraud flag: auto-notify admin to execute decoupling\n\n"
            "IMPORTANT: Dealer approval is NEVER required. Admin executes regardless."
        ),
    },
    {
        "name": "backend-location",
        "phase": 2,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/location/ with:\n"
            "  - POST /location/:deviceId/pull — dealer requests GPS pull\n"
            "    Sends FCM command to device requesting immediate GPS report\n"
            "    Device should respond within 60 seconds\n"
            "  - POST /location/:deviceId/report — device submits GPS data\n"
            "    Store: latitude, longitude, accuracy, timestamp, battery_level\n"
            "    Keep last 10 location pulls per device for duration of EMI\n"
            "  - GET /location/:deviceId/history — last 10 locations\n"
            "  - POST /location/:deviceId/geofence — dealer sets city/district boundary\n"
            "  - Geofence check: on each location report, check if device outside boundary\n"
            "    If outside boundary and device is locked: send alert to dealer\n"
            "  - Auto-location: when device enters Full Lock, schedule GPS pull every 6 hours "
            "(Bull queue recurring job)"
        ),
    },
    {
        "name": "backend-admin-api",
        "phase": 2,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/admin/ with:\n"
            "  - GET /admin/dashboard — summary stats: total devices, overdue count, "
            "locked count, decoupling pending\n"
            "  - GET /admin/resellers — list all resellers with status and stats\n"
            "  - POST /admin/resellers/:id/approve — approve reseller application\n"
            "  - POST /admin/resellers/:id/suspend — suspend reseller\n"
            "  - POST /admin/resellers/:id/quota — set monthly key quota\n"
            "  - GET /admin/devices — all devices across all dealers with filters\n"
            "  - POST /admin/devices/:id/lock — admin direct lock (any level)\n"
            "  - GET /admin/audit-log — paginated immutable audit log with filters\n"
            "  - GET /admin/security-events — fraud alerts and anomaly detections\n"
            "  - POST /admin/neir-queue — add device IMEI to NEIR reporting queue\n"
            "  - GET /admin/key-requests — pending key approval requests\n"
            "  - POST /admin/key-requests/:id/approve — approve with quantity\n"
            "  - All admin endpoints require admin role JWT + verified 2FA session"
        ),
    },
    {
        "name": "backend-fraud",
        "phase": 2,
        "model": "worker",
        "description": (
            "Create /backend/src/modules/fraud/ with:\n"
            "  - Play Integrity API webhook handler: POST /fraud/integrity-report\n"
            "    If attestation fails (rooted, tampered APK): auto-lock device, alert dealer\n"
            "  - Anomaly detection rules (run nightly via cron):\n"
            "    - Device location jumps > 200km in < 2 hours while locked\n"
            "    - Multiple IMEIs registered to same NID (except first)\n"
            "    - Device offline > 30 days while in overdue state\n"
            "    - Dealer with > 50% fraud flag rate\n"
            "  - POST /fraud/events — create security event record\n"
            "  - POST /fraud/resolve/:eventId — admin resolves a security event\n"
            "  - NEIR report queue: store devices flagged for BTRC submission\n"
            "    Generate Excel export in BTRC required format"
        ),
    },
    # ── Phase 3: User EMI App (Kotlin) ──────────────────────────────────────
    {
        "name": "user-app-foundation",
        "phase": 3,
        "model": "executor",
        "description": (
            "Create the Kotlin Android User EMI App foundation in /user-app/:\n\n"
            "build.gradle dependencies:\n"
            "  - AndroidX, Material Design 3\n"
            "  - Firebase Messaging (FCM)\n"
            "  - Play Integrity API\n"
            "  - Room database (local EMI schedule storage)\n"
            "  - WorkManager (background tasks)\n"
            "  - Retrofit + OkHttp with certificate pinning\n"
            "  - DataStore (encrypted shared prefs)\n\n"
            "Core components:\n"
            "  - EmiLockerDeviceAdminReceiver extends DeviceAdminReceiver:\n"
            "    onEnabled(): apply all Device Owner policies immediately\n"
            "    onDisableRequested(): re-lock device, return null (cannot be disabled)\n"
            "    onDisabled(): re-enroll immediately (should never happen)\n"
            "  - EmiLockerService extends Service:\n"
            "    Persistent foreground service with notification\n"
            "    DeviceAdminReceiver restarts it if killed\n"
            "    Handles FCM commands: LOCK, PARTIAL_LOCK, UNLOCK, DECOUPLE, MESSAGE\n"
            "  - DevicePolicyManager integration: apply all 8 policies on enrollment:\n"
            "    setGlobalSetting(ADB_ENABLED, 0)\n"
            "    setGlobalSetting(DEVELOPMENT_SETTINGS_ENABLED, 0)\n"
            "    setUsbDataSignalingEnabled(false)\n"
            "    setSecureSetting(INSTALL_NON_MARKET_APPS, 0)\n"
            "    setUninstallBlocked(true)\n"
            "    setApplicationHidden(false)\n"
            "  - AndroidManifest.xml with all required permissions and device admin metadata"
        ),
    },
    {
        "name": "user-app-lock-states",
        "phase": 3,
        "model": "executor",
        "description": (
            "Create the 6 lock state UI system for the Kotlin User EMI App:\n\n"
            "LockStateManager.kt — manages transitions between all 6 states:\n"
            "  NORMAL, REMINDER, WARNING, OVERDUE_ALERT, PARTIAL_LOCK, FULL_LOCK\n\n"
            "OverlayManager.kt — handles system overlay windows:\n"
            "  - Window type: TYPE_APPLICATION_OVERLAY\n"
            "  - Permission: SYSTEM_ALERT_WINDOW (granted at Device Owner level)\n"
            "  - NORMAL: no overlay\n"
            "  - REMINDER: push notification + app badge update only\n"
            "  - WARNING: persistent top banner overlay, dismissible for 4 hours\n"
            "  - OVERDUE_ALERT: full-screen overlay on every unlock, must acknowledge\n"
            "  - PARTIAL_LOCK: setPackagesSuspended() for all apps EXCEPT:\n"
            "    Phone, Messages, EMI app, Emergency dialer\n"
            "    Show overlay card with: amount due, days overdue, dealer name+phone, pay button\n"
            "  - FULL_LOCK: lockNow() + setLockTaskPackages([EMI app only])\n"
            "    Kiosk mode: only EMI app visible\n"
            "    Show: dealer contact, emergency call buttons (999 and 112 — ALWAYS available)\n\n"
            "CustomMessageOverlay.kt — dealer broadcast messages:\n"
            "  - Persistent overlay card shown even in Full Lock\n"
            "  - Dismissible but reappears every 30 min until marked read by dealer\n\n"
            "AutoLockScheduler.kt — local scheduler using WorkManager:\n"
            "  - Reads EMI schedule from local Room DB\n"
            "  - Fires lock transitions at correct times WITHOUT internet connection\n"
            "  - Schedule updated from server on every connection\n"
            "  - This is the offline failsafe — lock is NEVER missed due to network issues"
        ),
    },
    {
        "name": "user-app-paut",
        "phase": 3,
        "model": "worker",
        "description": (
            "Create the PAUT (Pre-Authorized Unlock Token) system in the Kotlin app:\n\n"
            "PautManager.kt:\n"
            "  - Store PAUT encrypted in DataStore (AES-256 via Android Keystore)\n"
            "  - PAUT is a signed JWT: {deviceImei, authorizedAt, expiresAt(48hr), nonce, hmacSig}\n"
            "  - verifyPaut(token): verify HMAC signature using embedded server public key\n"
            "    Reject if: expired, IMEI mismatch, signature invalid, already used\n"
            "  - checkAndExecutePaut(): called if FCM unlock not received within 2hr of authorized time\n"
            "    If valid PAUT exists: execute unlock without internet\n"
            "    Mark PAUT as used locally\n"
            "    Queue server report for next connection\n"
            "  - PadtManager.kt: same pattern for Pre-Authorized Decouple Token (7 day expiry)\n"
            "    On valid PADT: execute full decouple sequence offline\n\n"
            "CertificatePinner.kt:\n"
            "  - OkHttp CertificatePinner reads the API host from BuildConfig.API_BASE_URL\n"
            "  - In development (BuildConfig.DEBUG == true or host == 'localhost'): "
            "SKIP certificate pinning entirely so localhost works\n"
            "  - In production (non-localhost host): pin the SHA-256 fingerprint read from "
            "BuildConfig.SSL_PIN (set in build.gradle from environment variable)\n"
            "  - If pin fails in production: block all network requests, log security event\n"
            "  - BuildConfig fields to add in build.gradle:\n"
            "    buildConfigField 'String', 'API_BASE_URL', '\"http://10.0.2.2:3000\"'  "
            "// 10.0.2.2 = localhost from Android emulator\n"
            "    buildConfigField 'String', 'SSL_PIN', '\"REPLACE_BEFORE_PRODUCTION_BUILD\"'"
        ),
    },
    {
        "name": "user-app-dashboard",
        "phase": 3,
        "model": "worker",
        "description": (
            "Create the EMI Dashboard UI in the Kotlin User App:\n\n"
            "MainActivity.kt + activity_main.xml:\n"
            "  - EMI Summary card: total loan, amount paid, amount remaining, installments left\n"
            "  - Next Payment card: date, amount, countdown in days (prominent, colored by urgency)\n"
            "  - Lock Status indicator: Green(Active), Yellow(Due Soon), Orange(Overdue), Red(Locked)\n"
            "  - Quick actions: Contact Dealer (one-tap call + WhatsApp), View Agreement (PDF)\n"
            "  - Payment History: RecyclerView of all past payments\n"
            "  - Notification History: all reminders and dealer messages\n\n"
            "IMPORTANT — what user CANNOT do (enforced at system level, not UI level):\n"
            "  The UI simply reflects state. The actual enforcement is in DevicePolicyManager.\n"
            "  Do not try to enforce these in UI — they are OS-level.\n\n"
            "DealerContactActivity.kt:\n"
            "  - Shows dealer name, phone, shop name\n"
            "  - One-tap call button — accessible in ALL lock states including Full Lock\n"
            "  - WhatsApp button\n"
            "  - This activity must be in the setLockTaskPackages list for Full Lock"
        ),
    },
    # ── Phase 4: Dealer App (Flutter) ────────────────────────────────────────
    {
        "name": "dealer-app-foundation",
        "phase": 4,
        "model": "executor",
        "description": (
            "Create the Flutter Dealer + Reseller App foundation in /dealer-app/:\n\n"
            "pubspec.yaml dependencies:\n"
            "  - firebase_core, firebase_messaging (FCM)\n"
            "  - firebase_database (Realtime DB for live device status)\n"
            "  - dio (HTTP client with certificate pinning)\n"
            "  - flutter_secure_storage (token storage)\n"
            "  - local_auth (biometric for 2FA confirmation)\n"
            "  - qr_flutter (QR code generation for enrollment)\n"
            "  - mobile_scanner (barcode/IMEI scanning)\n"
            "  - image_picker (NID photo capture)\n"
            "  - syncfusion_flutter_charts (analytics charts)\n"
            "  - excel (NEIR export generation)\n\n"
            "Role-based app structure:\n"
            "  lib/main.dart — role detection at startup (DEALER or RESELLER)\n"
            "  lib/features/auth/ — login, 2FA setup, password change\n"
            "  lib/features/dealer/ — all dealer screens\n"
            "  lib/features/reseller/ — all reseller screens\n"
            "  lib/shared/ — common widgets, theme, API client, models\n\n"
            "AuthBloc — handles JWT storage, refresh, 2FA verification\n"
            "ApiClient — Dio client where base URL is read from .env via flutter_dotenv:\n"
            "  API_BASE_URL=http://10.0.2.2:3000  (Android emulator localhost)\n"
            "  API_BASE_URL=http://localhost:3000  (iOS simulator)\n"
            "  Certificate pinning: disabled when API_BASE_URL contains 'localhost' or '10.0.2.2'\n"
            "  Production: set API_BASE_URL to real domain, pinning auto-enables\n"
            "FirebaseService — listens to devices/{dealerId}/ for real-time status updates"
        ),
    },
    {
        "name": "dealer-app-enrollment",
        "phase": 4,
        "model": "worker",
        "description": (
            "Create the device enrollment flow in Flutter Dealer App:\n\n"
            "EnrollmentFlow (multi-step wizard):\n"
            "  Step 1 — Customer Details:\n"
            "    - Full name text field\n"
            "    - NID number field (validated format)\n"
            "    - NID photo capture via camera (image_picker)\n"
            "    - Phone number field\n"
            "  Step 2 — Device Info:\n"
            "    - IMEI entry: manual text input OR barcode scanner (mobile_scanner)\n"
            "    - IMEI validation: Luhn algorithm check\n"
            "    - Activation key selection from dealer's key inventory (dropdown)\n"
            "  Step 3 — EMI Schedule:\n"
            "    - Total price, down payment, monthly installment (auto-calculated)\n"
            "    - Duration in months (dropdown: 6, 12, 18, 24)\n"
            "    - Start date (date picker)\n"
            "    - Grace days (0-7, default 3)\n"
            "  Step 4 — QR Generation:\n"
            "    - Call API to create enrollment token\n"
            "    - Display QR code using qr_flutter\n"
            "    - Instructions: 'Power on phone, tap screen 6 times, scan this QR'\n"
            "    - Polling: check enrollment status every 5 seconds\n"
            "    - On enrollment confirmed: proceed to consent step\n"
            "  Step 5 — Consent Form:\n"
            "    - Display consent form text (from PRD Section 15)\n"
            "    - Customer signs on their phone (app shows 'waiting for customer signature')\n"
            "    - Dealer confirms on dealer app once customer has signed\n"
            "    - Both signatures timestamped and stored as PDF on server"
        ),
    },
    {
        "name": "dealer-app-device-management",
        "phase": 4,
        "model": "worker",
        "description": (
            "Create the device management screens in Flutter Dealer App:\n\n"
            "DeviceDashboard (home screen):\n"
            "  - Device list with status badges: Active, Reminder, Partial Lock, Full Lock, "
            "Paid Off, Compromised\n"
            "  - Summary cards: total devices, overdue count, upcoming EMIs this week, "
            "collection rate %\n"
            "  - Alert center: fraud alerts, anomaly detections, admin messages\n"
            "  - Real-time updates via Firebase Realtime DB listener\n\n"
            "DeviceDetailScreen (per device):\n"
            "  - Device info: IMEI, serial, OEM, model, Android version, enrollment date\n"
            "  - Current lock state with timestamp of last state change\n"
            "  - Last known GPS location with timestamp — tap to open Google Maps\n"
            "  - EMI schedule: all installments with paid/unpaid status\n"
            "  - Payment history: all recorded payments\n"
            "  - Customer info: name, NID, phone, NID photo (tap to view)\n"
            "  - Action buttons row:\n"
            "    [Request Lock] [Request Unlock] [Grant Grace Period] [Send Message] [Pull Location]\n\n"
            "LockRequestSheet (bottom sheet):\n"
            "  - Shows current EMI status prominently BEFORE dealer submits\n"
            "  - Reason dropdown (only valid codes shown based on overdue days)\n"
            "  - Optional note field (max 200 chars, char counter)\n"
            "  - 2FA confirmation: dealer must enter TOTP code to submit\n"
            "  - Loading state while server processes\n"
            "  - Result: green card (APPROVED) or red card (REJECTED with reason)\n"
            "  - If rejected: show in red: 'Your lock request is invalid. [Reason]. "
            "The device has NOT been locked.'"
        ),
    },
    {
        "name": "dealer-app-analytics",
        "phase": 4,
        "model": "worker",
        "description": (
            "Create analytics and NEIR export in Flutter Dealer App:\n\n"
            "AnalyticsScreen:\n"
            "  - Collection rate chart: % EMIs paid on time this month vs last month (bar chart)\n"
            "  - Overdue aging report: devices by days overdue (1-3, 3-7, 7-14, 14+ days)\n"
            "  - Device status breakdown: pie chart of all device states\n"
            "  - Revenue report: expected EMI income vs collected this month\n"
            "  - Key usage: keys purchased vs used vs available\n"
            "  All charts using syncfusion_flutter_charts\n\n"
            "NeireExportScreen:\n"
            "  - Button: 'Export for BTRC NEIR'\n"
            "  - Fetches all enrolled device IMEIs for this dealer from API\n"
            "  - Generates Excel file using the excel package\n"
            "  - BTRC required columns: IMEI, Device Brand, Model, Dealer NID, "
            "Dealer Business Name, Registration Date\n"
            "  - Share/download the Excel file\n"
            "  - Instructions text: 'Email this file to neir@btrc.gov.bd'"
        ),
    },
    # ── Phase 5: Reseller App + Admin Panel ─────────────────────────────────
    {
        "name": "reseller-app",
        "phase": 5,
        "model": "worker",
        "description": (
            "Create the Reseller screens in the Flutter app (role-switched from Dealer):\n\n"
            "ResellerDashboard:\n"
            "  - Dealer list with status: Active, Suspended, Pending\n"
            "  - Key inventory: keys purchased, assigned, available\n"
            "  - Monthly quota progress bar\n\n"
            "DealerManagementScreen:\n"
            "  - View dealer application details\n"
            "  - Approve/reject dealer with reason\n"
            "  - Suspend dealer (all their devices stay in current state)\n"
            "  - View dealer performance: activation rate, collection rate, key usage\n"
            "  - Assign keys to dealer (number input, confirm with 2FA)\n"
            "  - Reseller CANNOT access individual device data under any dealer\n\n"
            "KeyRequestScreen:\n"
            "  - Request keys: quantity input, justification text, submit\n"
            "  - Enforce: single request max 20% of monthly quota (client-side validation)\n"
            "  - View pending requests and their status\n"
            "  - View key inventory counts only (never show raw key strings)"
        ),
    },
    {
        "name": "admin-panel",
        "phase": 5,
        "model": "executor",
        "description": (
            "Create the Admin Web Panel in /admin-panel/ using React + Vite + TypeScript:\n\n"
            "Tech stack:\n"
            "  - React 18, TypeScript, Vite\n"
            "  - React Query (data fetching)\n"
            "  - Zustand (state management)\n"
            "  - React Router v6\n"
            "  - shadcn/ui components\n"
            "  - Recharts (charts)\n"
            "  - React Hook Form + Zod (forms)\n\n"
            "Pages:\n"
            "  /dashboard — system overview: total devices, overdue count, "
            "devices by lock state, revenue metrics\n"
            "  /devices — full device list with search, filter by state/dealer/overdue\n"
            "  /devices/:id — device detail: info, lock state, EMI schedule, location history, "
            "audit log for this device\n"
            "  /resellers — reseller management: approve, suspend, set quota\n"
            "  /key-requests — pending key approval queue with approve/reject actions\n"
            "  /decoupling — devices in 5-day window: pending admin action\n"
            "    Execute Decoupling button — requires 2FA modal confirmation\n"
            "  /audit-log — paginated immutable audit log with filters\n"
            "  /security-events — fraud alerts and anomaly detections with resolve action\n"
            "  /neir-queue — devices flagged for BTRC reporting\n\n"
            "Auth: JWT stored in httpOnly cookie, 2FA required on login and for destructive actions\n"
            "All destructive actions (lock, decouple, suspend) require 2FA re-confirmation modal"
        ),
    },
    # ── Phase 1 continued: Firebase + Express app entry ─────────────────────
    {
        "name": "backend-server-entry",
        "phase": 1,
        "model": "worker",
        "description": (
            "Create the Node.js + Express server entry point and configuration:\n\n"
            "/backend/src/app.js — Express app setup:\n"
            "  - Helmet (security headers)\n"
            "  - CORS (whitelist: app.emilocker.com, admin.emilocker.com)\n"
            "  - Rate limiting (express-rate-limit)\n"
            "  - Body parser with request size limits\n"
            "  - Morgan logging\n"
            "  - Mount all module routers\n\n"
            "/backend/src/server.js — HTTP server + graceful shutdown\n"
            "/backend/src/config/ — environment config (dotenv):\n"
            "  database, firebase, amapi, jwt_secret, hmac_secret, redis_url\n"
            "/backend/src/db/ — PostgreSQL connection pool (pg), migration runner\n"
            "/backend/src/firebase/ — firebase-admin SDK initialization\n"
            "/backend/src/redis/ — ioredis client for session + nonce storage\n"
            "/backend/package.json — all dependencies listed\n"
            "/backend/.env.example — document ALL environment variables with comments.\n"
            "  Include these URL vars with localhost defaults and a comment on each:\n"
            "  API_BASE_URL=http://localhost:3000  # Replace with real domain before deploy\n"
            "  ADMIN_PANEL_URL=http://localhost:5173  # Replace with real domain before deploy\n"
            "  CORS_ORIGIN=http://localhost:5173  # Replace with real domain before deploy\n"
            "  NODE_ENV=development\n"
            "  PORT=3000\n"
            "  POSTGRES_URL=postgresql://postgres:password@localhost:5432/emilocker_dev\n"
            "  REDIS_URL=redis://localhost:6379\n"
            "  JWT_SECRET=CHANGE_THIS_IN_PRODUCTION\n"
            "  HMAC_SECRET=CHANGE_THIS_IN_PRODUCTION\n"
            "  FIREBASE_PROJECT_ID=REPLACE_WITH_FIREBASE_PROJECT_ID\n"
            "  AMAPI_PROJECT_ID=REPLACE_WITH_GOOGLE_CLOUD_PROJECT_ID\n"
            "/backend/.env — copy of .env.example with dev values filled in (gitignored)\n"
            "/backend/Dockerfile — Node.js 20 Alpine image\n"
            "/backend/docker-compose.yml — backend + postgres + redis services\n"
            "  Use localhost ports: postgres on 5432, redis on 6379, backend on 3000"
        ),
    },
]


class EmiLockerBuilder:
    def __init__(self, project_dir: str = ".", mode: str = "prototype"):
        self.mode = mode
        self.project_dir = Path(project_dir)
        self.log_file    = self.project_dir / "build_log.md"
        self.state_file  = self.project_dir / "build_state.json"
        self.prd_file    = self.project_dir / "EMI_Locker_PRD_v3.txt"

        # Load PRD content once
        if self.prd_file.exists():
            self.prd_content = self.prd_file.read_text(encoding="utf-8")
        else:
            self.prd_content = "[PRD file not found — models will use their training knowledge]"

        # Load compressed PRD summary (generated on first run, reused on all subsequent calls)
        self.summary_file = self.project_dir / "prd_summary.md"
        self.prd_summary  = self._load_or_skip_summary()

        # Load or init state
        self.state = self._load_state()

        # RLock (reentrant) — same thread can acquire multiple times without deadlock
        self._log_lock   = threading.RLock()
        self._state_lock = threading.RLock()

    # ── PRD summary (one-time compression, reused every call) ────────────────

    def _load_or_skip_summary(self) -> str:
        """Load cached summary if it exists. Generated on first executor call."""
        if self.summary_file.exists():
            return self.summary_file.read_text(encoding="utf-8")
        return ""  # Will be generated on first executor_build_plan() call

    def _generate_and_cache_summary(self, raw_response: str):
        """Extract and cache the PRD summary so we never send the full PRD again."""
        if self.summary_file.exists():
            return
        # Save executor's own understanding as the reusable summary
        summary = (
            "# EMI Locker PRD — Compressed Summary (auto-generated by Executor)\n\n"
            + raw_response[:6000]  # cap at 6k words — enough context, not bloated
        )
        self.summary_file.write_text(summary, encoding="utf-8")
        self.prd_summary = summary

    # ── Logging ──────────────────────────────────────────────────────────────

    def log(self, msg: str, level: str = "INFO"):
        ts    = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        entry = f"[{ts}] [{level}] {msg}"
        with self._log_lock:
            print(entry)
            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(entry + "\n")

    # ── State persistence ─────────────────────────────────────────────────────

    def _load_state(self) -> dict:
        if self.state_file.exists():
            try:
                # Use utf-8-sig to gracefully handle Windows BOMs
                return json.loads(self.state_file.read_text(encoding="utf-8-sig"))
            except Exception as e:
                self.log(f"ERROR: Failed to parse build_state.json: {e}", "ERROR")
                # If file exists and has data but fails to parse, DO NOT return empty state.
                # Return empty only if file is genuinely empty to avoid wiping hours of progress.
                if len(self.state_file.read_text(encoding="utf-8-sig").strip()) > 10:
                    self.log("ERROR: State file has content but is corrupted. Halting to prevent data loss.", "ERROR")
                    sys.exit(1)
        return {"completed": [], "failed": [], "started_at": datetime.now().isoformat()}

    def _save_state(self):
        with self._state_lock:
            self.state_file.write_text(json.dumps(self.state, indent=2), encoding="utf-8")

    # ── OpenCode runner ───────────────────────────────────────────────────────

    def _run_opencode(self, model: str, prompt: str, timeout: int = 600) -> str | None:
        if model in ("gemini-cli", "gemini-cli-yolo"):
            return self._run_gemini_supervisor(prompt, timeout)
            
        # Pass prompt via stdin — avoids Windows cmd-line length limits and
        # all shell escaping issues. opencode run reads stdin when no message is given.
        # shell=True required so Windows finds opencode.cmd in npm PATH.
        # Note: run this script in FOREGROUND (not background) for reliable output capture.
        cmd = f'opencode run -m "{model}"'
        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(self.project_dir),
                timeout=timeout,
                shell=True,
            )
            output = result.stdout.strip()
            if result.returncode == 0 and output:
                return output
            # opencode sometimes writes response to stderr (debug builds)
            stderr = result.stderr.strip()
            if stderr and "error" not in stderr.lower()[:50]:
                return stderr
            if stderr:
                self.log(f"OpenCode stderr: {stderr[:300]}", "WARN")
            self.log(f"OpenCode exit code {result.returncode}", "WARN")
            return None
        except subprocess.TimeoutExpired:
            self.log(f"Timeout after {timeout}s for model {model}", "ERROR")
            return None
        except Exception as exc:
            self.log(f"Exception running OpenCode: {exc}", "ERROR")
            return None

    def start_supervisor_watcher(self) -> None:
        if os.environ.get("DISABLE_SUPERVISOR_WATCH") == "1":
            self.log("SUPERVISOR_WATCH: disabled by environment.")
            return
        watcher = self.project_dir / "supervisor_watcher.py"
        if not watcher.exists():
            self.log("SUPERVISOR_WATCH: supervisor_watcher.py not found.", "WARN")
            return

        try:
            subprocess.Popen(
                [
                    sys.executable,
                    str(watcher),
                    "--project-dir",
                    str(self.project_dir),
                    "--from-end",
                    "--stop-after-complete",
                ],
                cwd=str(self.project_dir),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            self.log("SUPERVISOR_WATCH: Codex live watcher launch requested.")
        except Exception as exc:
            self.log(f"SUPERVISOR_WATCH: failed to launch: {exc}", "WARN")

    # Supervisor (Codex) - final audit hook

    def _run_supervisor(self, prompt: str, timeout: int = 600) -> str | None:
        if shutil.which("codex"):
            model = os.environ.get("CODEX_SUPERVISOR_MODEL", SUPERVISOR_MODEL)
            output_file = self.project_dir / ".codex_supervisor_last.txt"
            if output_file.exists():
                output_file.unlink()
            cmd = f'codex exec -m "{model}" --skip-git-repo-check --sandbox danger-full-access -o ".codex_supervisor_last.txt" -C . -'
            try:
                result = subprocess.run(
                    cmd,
                    input=prompt,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    cwd=str(self.project_dir),
                    timeout=timeout,
                    shell=True,
                )
                if output_file.exists():
                    output = output_file.read_text(encoding="utf-8").strip()
                    if output:
                        return output
                output = result.stdout.strip()
                if result.returncode == 0 and output:
                    return output
                stderr = result.stderr.strip()
                if stderr:
                    self.log(f"SUPERVISOR ({SUPERVISOR_NAME}) Codex CLI stderr: {stderr[:300]}", "WARN")
            except subprocess.TimeoutExpired:
                self.log(f"SUPERVISOR ({SUPERVISOR_NAME}) Codex CLI timeout after {timeout}s", "ERROR")
            except Exception as exc:
                self.log(f"Exception running Codex CLI supervisor: {exc}", "ERROR")

        cli_path = self.project_dir / SUPERVISOR_CLI
        if not cli_path.exists():
            self.log(f"SUPERVISOR ({SUPERVISOR_NAME}): {SUPERVISOR_CLI} not found; skipping audit.", "WARN")
            return None

        cmd = [sys.executable, str(cli_path), "--stdin"]
        try:
            result = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(self.project_dir),
                timeout=timeout,
            )
            output = result.stdout.strip()
            if result.returncode == 0 and output:
                return output
            stderr = result.stderr.strip()
            if stderr:
                self.log(f"SUPERVISOR ({SUPERVISOR_NAME}) stderr: {stderr[:300]}", "WARN")
            return None
        except subprocess.TimeoutExpired:
            self.log(f"SUPERVISOR ({SUPERVISOR_NAME}) timeout after {timeout}s", "ERROR")
            return None
        except Exception as exc:
            self.log(f"Exception running SUPERVISOR ({SUPERVISOR_NAME}): {exc}", "ERROR")
            return None

    def _clean_gemini_output(self, raw: str) -> str:
        """Strip MCP/UI noise lines from Gemini CLI headless output."""
        noise_prefixes = (
            "mcp issues detected",
            "ripgrep is not available",
            "warning: windows",
            "warning: 256-color",
            "warning:",
        )
        cleaned = []
        for line in raw.splitlines():
            if any(line.strip().lower().startswith(p) for p in noise_prefixes):
                continue
            cleaned.append(line)
        return "\n".join(cleaned).strip()

    def _run_gemini_supervisor(self, prompt: str, timeout: int = 600) -> str | None:
        """
        Run Gemini CLI headlessly with --yolo --skip-trust.
        Writes prompt to a temp file so Gemini reads it via its Read tool —
        Gemini ignores stdin when -p is given, so temp file is the only reliable way.
        """
        self.log("EXECUTOR (gemini-cli --yolo): Running headless...")
        tmp = self.project_dir / f"_gemini_prompt_{int(time.time())}.txt"
        try:
            tmp.write_text(prompt, encoding="utf-8")
            stub = f"Read the file '{tmp}' and follow all instructions in it exactly."
            # Escape backslashes and quotes for cmd.exe
            stub_escaped = stub.replace("\\", "\\\\").replace('"', '\\"')
            cmd = f'gemini --yolo --skip-trust -p "{stub_escaped}"'
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(self.project_dir),
                timeout=timeout,
                shell=True,
            )
            output = self._clean_gemini_output(result.stdout.strip())
            if result.returncode == 0 and output:
                return output
            stderr = result.stderr.strip()
            if stderr:
                self.log(f"EXECUTOR (gemini-cli) stderr: {stderr[:300]}", "WARN")
            self.log(f"EXECUTOR (gemini-cli): exit code {result.returncode}", "WARN")
            return None
        except subprocess.TimeoutExpired:
            self.log(f"EXECUTOR (gemini-cli): Timeout after {timeout}s", "ERROR")
            return None
        except Exception as exc:
            self.log(f"EXECUTOR (gemini-cli): Exception: {exc}", "ERROR")
            return None
        finally:
            tmp.unlink(missing_ok=True)

    def _run_claude_cli(self, model: str, prompt: str, timeout: int) -> str | None:
        """
        Run Claude Code CLI (claude) as executor/reviewer.
        Writes prompt to a temp file so Claude reads it via its own Read tool —
        avoids Windows 32k command-line length limit entirely.
        Uses --dangerously-skip-permissions so no interactive prompts block the build.
        """
        tmp = self.project_dir / f"_claude_task_{int(time.time())}.txt"
        try:
            tmp.write_text(prompt, encoding="utf-8")
            stub = f"Read the file '{tmp}' and follow all instructions in it exactly."
            # < nul suppresses the 'no stdin data' warning from Claude CLI
            cmd = (
                f'claude --model {model} --dangerously-skip-permissions '
                f'--output-format text -p "{stub}" < nul'
            )
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(self.project_dir),
                timeout=timeout,
                shell=True,
            )
            output = result.stdout.strip()
            # Strip any residual warning lines
            output = "\n".join(
                ln for ln in output.splitlines()
                if not ln.startswith("Warning:") and not ln.startswith("⚠")
            ).strip()
            if result.returncode == 0 and output:
                return output
            stderr = result.stderr.strip()
            if stderr:
                self.log(f"Claude CLI ({model}) stderr: {stderr[:300]}", "WARN")
            self.log(f"Claude CLI ({model}) exit code {result.returncode}", "WARN")
            return None
        except subprocess.TimeoutExpired:
            self.log(f"Timeout after {timeout}s for Claude {model}", "ERROR")
            return None
        except Exception as exc:
            self.log(f"Exception running Claude CLI ({model}): {exc}", "ERROR")
            return None
        finally:
            tmp.unlink(missing_ok=True)

    def supervisor_final_audit(self, completed: list, failed: list) -> str | None:
        # ── Step 0: Request Gemini CLI (First Frontier Supervisor) ─────────────
        self.log("AUDIT (Gemini/Antigravity): Build complete — requesting FIRST FRONTIER audit via Gemini CLI.")
        prompt = (
            "You are Antigravity, the FIRST FRONTIER SUPERVISOR AI for the EMI Locker Platform.\n"
            "Phase 1 build is complete. Audit the build state and produce a concise report with:\n"
            "overall verdict, high-risk gaps, failed modules analysis, next actions, "
            "and whether Phase 2 is allowed to start.\n\n"
            f"Completed modules: {completed}\n"
            f"Failed modules: {failed}\n\n"
        )
        result = self._run_gemini_supervisor(prompt, TIMEOUT_REVIEW)
        if result:
            audit_file = self.project_dir / "SUPERVISOR_AUDIT.md"
            audit_file.write_text(f"# Audit by Antigravity (Gemini CLI)\n\n{result}\n", encoding="utf-8")
            self.log("AUDIT (Gemini/Antigravity): First frontier audit complete. Report written.")
            return result

        # ── Step 1: Request Claude (Heavy Lifter Supervisor) ────────────────────
        self.log(f"AUDIT (Gemini Failed/Unavailable): Falling back to Heavy Lifter — requesting Claude audit.")

        # Write request file — Claude's Stop hook fires on every reply turn and picks this up
        request_file = self.project_dir / "CLAUDE_SUPERVISOR_REQUEST.json"
        response_flag = self.project_dir / PRIMARY_SUPERVISOR_FLAG
        response_flag.unlink(missing_ok=True)  # clear any stale flag

        import json as _json
        request_file.write_text(_json.dumps({
            "trigger":   "BUILD_COMPLETE",
            "completed": completed,
            "failed":    failed,
            "timestamp": datetime.now().isoformat(),
            "instruction": (
                "Claude: Phase 1 build is complete. Please audit the generated code against "
                "the PRD, check all failed modules, verify security requirements, and write "
                "your findings to CLAUDE_SUPERVISOR_RESPONSE.flag to confirm audit is done."
            ),
        }, indent=2), encoding="utf-8")

        # ── Step 2: Wait for Claude to respond ────────────────────────────
        # Claude's Stop hook fires at the end of every reply turn (seconds away
        # when the session is active). We poll for up to CLAUDE_SUPERVISOR_TIMEOUT,
        # logging every 30s so the monitor shows progress without spamming.
        self.log(f"AUDIT ({PRIMARY_SUPERVISOR}): Request written. Waiting up to {CLAUDE_SUPERVISOR_TIMEOUT}s for Claude Stop-hook response...")

        waited = 0
        poll_interval = 5   # check every 5s — flag appears within seconds once Claude replies
        log_every     = 30  # only log progress every 30s to keep log clean
        next_log      = log_every
        while waited < CLAUDE_SUPERVISOR_TIMEOUT:
            time.sleep(poll_interval)
            waited += poll_interval
            if response_flag.exists():
                self.log(f"AUDIT ({PRIMARY_SUPERVISOR}): Claude responded after {waited}s. Primary audit complete.")
                audit_file = self.project_dir / "SUPERVISOR_AUDIT.md"
                try:
                    content = response_flag.read_text(encoding="utf-8").strip()
                    audit_file.write_text(f"# Audit by {PRIMARY_SUPERVISOR}\n\n{content}\n", encoding="utf-8")
                except Exception:
                    pass
                return f"Claude audit confirmed after {waited}s."
            if waited >= next_log:
                self.log(f"AUDIT ({PRIMARY_SUPERVISOR}): Still waiting... ({waited}/{CLAUDE_SUPERVISOR_TIMEOUT}s)")
                next_log += log_every

        # ── Step 3: Claude did not respond — fall back to Codex ───────────
        # Only reaches here if Claude is genuinely offline for the full timeout window.
        self.log(f"AUDIT ({PRIMARY_SUPERVISOR}): No response after {CLAUDE_SUPERVISOR_TIMEOUT}s — session likely offline.")
        self.log(f"AUDIT (Fallback -> {SUPERVISOR_NAME}): Routing to secondary supervisor.")

        prompt = (
            f"You are {SUPERVISOR_NAME}, the SECONDARY SUPERVISOR AI for the EMI Locker Platform.\n"
            f"The primary supervisor ({PRIMARY_SUPERVISOR}) did not respond. You are taking over.\n"
            "Do not implement new code. Audit the build state and produce a concise report with:\n"
            "overall verdict, high-risk gaps, failed modules analysis, next actions, "
            "and whether Phase 2 is allowed to start.\n\n"
            f"Completed modules: {completed}\n"
            f"Failed modules: {failed}\n\n"
            "Inspect from workspace:\n"
            "- build_log.md\n- build_state.json\n- backend/src/modules/\n"
        )
        result = self._run_supervisor(prompt, TIMEOUT_REVIEW)
        if result:
            audit_file = self.project_dir / "SUPERVISOR_AUDIT.md"
            audit_file.write_text(f"# Audit by {SUPERVISOR_NAME} (fallback — {PRIMARY_SUPERVISOR} unavailable)\n\n{result}\n", encoding="utf-8")
            self.log(f"AUDIT ({SUPERVISOR_NAME}): Fallback audit complete. Report written.")
        return result
    # ── Executor (MIMO 1M) — plan + review ───────────────────────────────────

    def executor_build_plan(self) -> list[dict] | None:
        self.log("EXECUTOR (gemini-cli --yolo): Reading PRD and building implementation plan...")
        if self.prd_summary:
            self.log("EXECUTOR: PRD analysis complete.")
            return self.prd_summary
        prompt = (
            "You are the EXECUTOR AI (Gemini CLI) for the EMI Locker Platform.\n\n"
            f"{DEV_URL_INSTRUCTION}\n\n"
            "Read the following PRD carefully, then confirm you understand the full system "
            "by listing the 5 most critical security requirements and the correct build order "
            "for Phase 1. Output as JSON:\n"
            '{"understood": true, "critical_security": ["...", "..."], '
            '"phase1_order": ["module1", "module2", ...]}\n\n'
            f"=== PRD START ===\n{self.prd_content}\n=== PRD END ==="
        )
        result = self._run_gemini_supervisor(prompt, TIMEOUT_PLAN)
        if result:
            self.log("EXECUTOR: PRD analysis complete.")
            self._generate_and_cache_summary(result)
        return result

    def _collect_module_files(self, module_name: str) -> str:
        """Read key source files for a module from disk to give the reviewer ground truth."""
        # Map module names to directory hints
        dir_hints = {
            "dealer-app": ["dealer-app/lib"],
            "user-app":   ["user-app/app/src/main/java"],
            "backend":    ["backend/src"],
            "admin-panel":["admin-panel/src"],
            "reseller":   ["dealer-app/lib/features/reseller"],
        }
        search_dirs = []
        for key, dirs in dir_hints.items():
            if key in module_name:
                search_dirs.extend(dirs)
        if not search_dirs:
            search_dirs = ["backend/src", "dealer-app/lib", "user-app/app/src"]

        collected = []
        total_chars = 0
        MAX_CHARS = 12000  # cap to avoid blowing context window
        EXTS = {".dart", ".kt", ".js", ".ts", ".tsx", ".py", ".sql"}

        for rel_dir in search_dirs:
            base = self.project_dir / rel_dir
            if not base.exists():
                continue
            for fpath in sorted(base.rglob("*")):
                if fpath.suffix not in EXTS:
                    continue
                if total_chars >= MAX_CHARS:
                    break
                try:
                    content = fpath.read_text(encoding="utf-8", errors="replace")
                    snippet = content[:2000]  # cap per file
                    rel = str(fpath.relative_to(self.project_dir)).replace("\\", "/")
                    collected.append(f"// === {rel} ===\n{snippet}")
                    total_chars += len(snippet)
                except Exception:
                    pass

        return "\n\n".join(collected) if collected else "(no files found on disk)"

    def executor_review(self, module_name: str, summary: str) -> dict:
        self.log(f"EXECUTOR (Claude): Reviewing {module_name}...")
        prd_ref = self.prd_summary if self.prd_summary else self.prd_content[:5000]
        # Inject REAL file contents so reviewer judges actual code, not a vague summary
        real_files = self._collect_module_files(module_name)
        prompt = (
            f"You are a Code Reviewer for the EMI Locker Platform.\n"
            f"Review the implementation of module: {module_name}\n\n"
            "This is a SECURITY-CRITICAL Android MDM app. Score strictly. 95+ = PRODUCTION READY.\n\n"
            "IMPORTANT: Base your review on the ACTUAL FILE CONTENTS below, not on the worker summary.\n\n"
            f"=== ACTUAL FILE CONTENTS ON DISK ===\n{real_files}\n\n"
            f"=== WORKER IMPLEMENTATION NOTES ===\n{summary[:1000]}\n\n"
            "Score rubric (start at 100, deduct):\n"
            "  -20 per HIGH   (runtime crash, auth bypass, data loss, wrong API call)\n"
            "  -10 per MEDIUM (missing PRD feature, weak validation, wrong abstraction)\n"
            "   -3 per LOW    (code style, redundant logic)\n\n"
            "Award 95+ ONLY if ALL pass:\n"
            "  - Every endpoint in PRD spec present and correctly implemented\n"
            "  - No runtime crashes, undefined references, missing imports\n"
            "  - All auth/RBAC middleware applied — no unprotected endpoint\n"
            "  - No SQL injection, no hardcoded secrets, no auth bypass\n"
            "  - All state machine transitions match PRD exactly\n"
            "  - HMAC signing, JWT verification, 2FA checks present where required\n\n"
            "Status: 'approved' = score>=95 AND no HIGH issues. Otherwise 'needs_changes'.\n\n"
            "CRITICAL INSTRUCTION: Output RAW JSON ONLY. Do NOT use markdown code blocks (```json). Do NOT add ANY conversational text before or after the JSON.\n"
            '{"status": "approved|needs_changes", "score": 0-100, '
            '"issues": [{"severity": "high|medium|low", "description": "...", "fix": "..."}]}\n\n'
            f"=== PRD REFERENCE ===\n{prd_ref}"
        )
        result = self._run_claude_cli("claude-opus-4-7", prompt, TIMEOUT_REVIEW)
        if result:
            self.log(f"EXECUTOR (Claude) raw output ({len(result)} chars): {result[:200]}...")
            parsed = self._parse_review_json(module_name, result, "Claude")
            if parsed:
                return parsed

        # ── Claude failed — try local review from supervisor file-hook ──────────
        # Antigravity (supervisor in the chat window) can write a review_response.json
        # to the project root at any time. This is the most reliable fallback.
        self.log(f"[{module_name}] Claude unavailable — checking for supervisor file-review hook.", "WARN")
        parsed = self._check_supervisor_file_review(module_name)
        if parsed:
            return parsed

        # ── Last resort: local structural review (no external AI needed) ─────────
        self.log(f"[{module_name}] No supervisor response — running local structural review.", "WARN")
        return self._local_structural_review(module_name)

    def _check_supervisor_file_review(self, module_name: str) -> dict | None:
        """
        Polls for a review file written by the supervisor (Antigravity) in the chat window.
        The supervisor writes D:\\EMI APP\\review_response.json with the standard review schema.
        The builder picks it up, consumes it (deletes it), and returns the parsed result.
        """
        response_file = self.project_dir / "review_response.json"
        request_file  = self.project_dir / "review_request.json"

        # Write a review request so the supervisor knows what to review
        try:
            import json as _json
            request_file.write_text(_json.dumps({
                "module": module_name,
                "timestamp": datetime.now().isoformat(),
                "instruction": (
                    f"Supervisor: Please review module '{module_name}'. "
                    "Read the actual source files in the project, then write your "
                    "review to review_response.json using the schema: "
                    '{\"status\": \"approved|needs_changes\", \"score\": 0-100, '
                    '\"issues\": [{\"severity\": \"high|medium|low\", \"description\": \"...\", \"fix\": \"...\"}]}'
                )
            }, indent=2), encoding="utf-8")
            self.log(f"[{module_name}] Supervisor review requested → review_request.json written.", "WARN")
        except Exception:
            pass

        # Poll up to 3 minutes for supervisor response
        for _ in range(36):
            time.sleep(5)
            if response_file.exists():
                try:
                    raw = response_file.read_text(encoding="utf-8")
                    parsed = self._parse_review_json(module_name, raw, "Supervisor-file")
                    if parsed:
                        score = parsed.get("score", 0)
                        pass_threshold = 60 if self.mode == "prototype" else 90
                        
                        if parsed.get("status") == "approved" and score >= pass_threshold:
                            self.log(f"[{module_name}] Supervisor file approved: score={score}")
                            if response_file.exists():
                                response_file.unlink()
                            if request_file.exists():
                                request_file.unlink()
                            return parsed
                except Exception as e:
                    self.log(f"[{module_name}] Supervisor file parse error: {e}", "WARN")
        return None

    def _local_structural_review(self, module_name: str) -> dict:
        """
        A fast, zero-dependency local review that checks the file system directly.
        Looks for the presence of expected files and flags obvious issues.
        Falls back to this when all AI reviewers are unavailable.
        """
        issues = []
        score = 100
        module_dir_map = {
            "dealer-app-foundation":       self.project_dir / "dealer-app" / "lib",
            "dealer-app-device-management":self.project_dir / "dealer-app" / "lib" / "features",
            "dealer-app-analytics":        self.project_dir / "dealer-app" / "lib" / "features",
            "reseller-app":                self.project_dir / "dealer-app" / "lib" / "features" / "reseller",
            "admin-panel":                 self.project_dir / "admin-panel" / "src",
        }
        target_dir = module_dir_map.get(module_name)
        if target_dir and target_dir.exists():
            dart_files = list(target_dir.rglob("*.dart"))
            if len(dart_files) < 3:
                issues.append({"severity": "high", "description": f"Only {len(dart_files)} .dart files found — module appears incomplete.", "fix": "Implement all required screens, BLoCs, repositories, and models."})
                score -= 20
            # Check for hardcoded URLs
            for f in dart_files[:20]:
                try:
                    txt = f.read_text(encoding="utf-8", errors="replace")
                    if "http://localhost" in txt or "192.168." in txt:
                        issues.append({"severity": "high", "description": f"Hardcoded URL found in {f.name}", "fix": "Replace with EnvConfig.apiBaseUrl"})
                        score -= 20
                        break
                except Exception:
                    pass
        else:
            issues.append({"severity": "high", "description": f"Module directory not found: {target_dir}", "fix": "Create the required directory and implement all module files."})
            score -= 40

        status = "approved" if score >= 95 and not any(i["severity"] == "high" for i in issues) else "needs_changes"
        self.log(f"[{module_name}] Local structural review → score={score}, status={status}")
        return {"status": status, "score": max(0, score), "issues": issues}



    def _parse_review_json(self, module_name: str, result: str, source: str) -> dict | None:
        """Robustly extract JSON from a reviewer response regardless of markdown wrapping."""
        try:
            stripped = result.strip()
            if "```json" in stripped:
                stripped = stripped.split("```json")[1].split("```")[0].strip()
            elif "```" in stripped:
                parts = stripped.split("```")
                if len(parts) >= 3:
                    stripped = parts[1].strip()

            # Strategy 1: try direct parse (cleanest — works when output is pure JSON)
            start = stripped.find("{")
            if start != -1:
                try:
                    parsed = json.loads(stripped[start:])
                    self.log(f"EXECUTOR ({source}) parsed (direct): {parsed.get('status')}, score={parsed.get('score')}")
                    return parsed
                except json.JSONDecodeError:
                    pass

            # Strategy 2: rfind last } and try the slice (handles trailing text)
            if start != -1:
                end = stripped.rfind("}") + 1
                if end > start:
                    try:
                        parsed = json.loads(stripped[start:end])
                        self.log(f"EXECUTOR ({source}) parsed (rfind): {parsed.get('status')}, score={parsed.get('score')}")
                        return parsed
                    except json.JSONDecodeError:
                        pass

            self.log(f"EXECUTOR ({source}) JSON not found in output (len={len(result)})", "WARN")
        except Exception as e:
            self.log(f"EXECUTOR ({source}) JSON parse error: {e}", "WARN")
        return None


    def _fallback_review(self, module_name: str, summary: str) -> dict | None:
        if module_name == "project-structure":
            return self._review_project_structure()
        prd_ref = self.prd_summary if self.prd_summary else self.prd_content[:3000]
        prompt = (
            f"You are reviewing module: {module_name}\n\n"
            f"Implementation summary:\n{summary[:2000]}\n\n"
            "Output JSON only:\n"
            '{"status": "approved|needs_changes", "score": 0-100, '
            '"issues": [{"severity": "high|medium|low", "description": "...", "fix": "..."}]}\n\n'
            f"=== PRD ===\n{prd_ref}"
        )
        result = subprocess.run(
            f'opencode run -m "{WORKER_MODEL}"',
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(self.project_dir),
            timeout=480,
            shell=True,
        )
        output = result.stdout.strip() or result.stderr.strip()
        if output:
            try:
                stripped = output.strip()
                start = stripped.find("{")
                end   = stripped.rfind("}") + 1
                if start != -1 and end > start:
                    return json.loads(stripped[start:end])
            except json.JSONDecodeError:
                pass
        return None

    def _review_project_structure(self) -> dict:
        self.log("EXECUTOR: Performing local review of project-structure...")
        checks = []
        score = 100
        issues = []

        required_dirs = ["backend", "user-app", "dealer-app", "admin-panel", "database", "firebase"]
        for d in required_dirs:
            p = self.project_dir / d
            if p.exists() and p.is_dir():
                checks.append(f"✓ {d}/ exists")
            else:
                checks.append(f"✗ {d}/ MISSING")
                issues.append({"severity": "high", "description": f"Required directory {d}/ not found", "fix": f"Create {d}/ directory"})
                score -= 20

        backend_pkg = self.project_dir / "backend" / "package.json"
        if backend_pkg.exists():
            checks.append("✓ backend/package.json")
            try:
                pkg = json.loads(backend_pkg.read_text(encoding="utf-8"))
                if "scripts" in pkg and "start" in pkg["scripts"]:
                    checks.append("✓ backend/package.json scripts.start")
                else:
                    issues.append({"severity": "medium", "description": "backend/package.json missing scripts.start", "fix": "Add start script"})
                    score -= 10
            except Exception:
                issues.append({"severity": "medium", "description": "backend/package.json is invalid JSON", "fix": "Fix package.json"})
                score -= 10
        else:
            checks.append("✗ backend/package.json MISSING")
            issues.append({"severity": "high", "description": "backend/package.json not found", "fix": "Create backend/package.json"})
            score -= 20

        dealer_yaml = self.project_dir / "dealer-app" / "pubspec.yaml"
        if dealer_yaml.exists():
            checks.append("✓ dealer-app/pubspec.yaml")
        else:
            checks.append("✗ dealer-app/pubspec.yaml MISSING")
            issues.append({"severity": "high", "description": "dealer-app/pubspec.yaml not found", "fix": "Create dealer-app/pubspec.yaml"})
            score -= 20

        admin_pkg = self.project_dir / "admin-panel" / "package.json"
        if admin_pkg.exists():
            checks.append("✓ admin-panel/package.json")
        else:
            checks.append("✗ admin-panel/package.json MISSING")
            issues.append({"severity": "high", "description": "admin-panel/package.json not found", "fix": "Create admin-panel/package.json"})
            score -= 20

        user_gradle = self.project_dir / "user-app" / "build.gradle"
        if user_gradle.exists():
            checks.append("✓ user-app/build.gradle")
        else:
            checks.append("✗ user-app/build.gradle MISSING")
            issues.append({"severity": "high", "description": "user-app/build.gradle not found", "fix": "Create user-app/build.gradle"})
            score -= 20

        db_migrations = self.project_dir / "database" / "migrations"
        if db_migrations.exists() and db_migrations.is_dir():
            migration_files = list(db_migrations.glob("*.sql"))
            if len(migration_files) >= 5:
                checks.append(f"✓ database/migrations/ ({len(migration_files)} files)")
            else:
                issues.append({"severity": "medium", "description": f"database/migrations/ has only {len(migration_files)} files, expected many", "fix": "Add all migration files"})
                score -= 10
        else:
            issues.append({"severity": "high", "description": "database/migrations/ not found", "fix": "Create database/migrations/ with schema files"})
            score -= 20

        fb_readme = self.project_dir / "firebase" / "README.md"
        if fb_readme.exists():
            checks.append("✓ firebase/README.md")
        else:
            issues.append({"severity": "low", "description": "firebase/README.md not found", "fix": "Create firebase/README.md"})
            score -= 3

        pass_threshold = 60 if self.mode == "prototype" else 90
        status = "approved" if score >= pass_threshold and not any(i["severity"] == "high" for i in issues) else "needs_changes"
        self.log(f"EXECUTOR: project-structure local review → score={score} status={status}")
        for c in checks:
            self.log(f"  {c}")
        if issues:
            for i in issues:
                self.log(f"  ISSUE [{i['severity']}] {i['description']}")
        return {"status": status, "score": max(0, score), "issues": issues}

    # ── Worker (MINIMAX 256k) — implementation ────────────────────────────────

    def _worker_prompt_implement(self, module: dict, worker_name: str) -> str:
        skill_pack = PROTOTYPE_SKILLS if self.mode == "prototype" else PRODUCTION_SKILLS
        return (
            f"You are {worker_name} — Worker AI implementing module: {module['name']}\n"
            f"Phase {module['phase']} of the EMI Locker Platform.\n\n"
            f"{skill_pack}\n\n"
            f"{DEV_URL_INSTRUCTION}\n\n"
            f"TASK:\n{module['description']}\n\n"
            "INSTRUCTIONS:\n"
            "1. Create ALL files described using your Write/Edit tools\n"
            "2. Write complete, working code — no placeholders or TODO comments\n"
            "3. Follow the exact file paths specified\n"
            "4. Use proper error handling throughout\n"
            "5. Security first — validate all inputs, never trust client data\n"
            "6. Every URL must come from environment variables — see DEV_URL_INSTRUCTION above\n\n"
            "PRD CONTEXT (key sections relevant to this module):\n"
            f"{self._prd_excerpt(module['name'])}\n\n"
            "Start implementing now. Create all files."
        )

    def _run_implement_and_fix(self, module: dict, worker_name: str, worker_model: str, max_fix_iterations: int = 5) -> bool:
        """Runs the implementation and fix loop for a single module using a SINGLE given worker model."""
        name = module['name']
        self.log(f"[{name}] {worker_name} ({worker_model}): Implementing...")
        prompt = self._worker_prompt_implement(module, worker_name)
        
        # Implement
        impl = self._run_opencode(worker_model, prompt, TIMEOUT_BUILD)
        if not impl:
            return False
            
        # Executor reviews
        review = self.executor_review(name, impl)
        self.log(f"[{name}] Review: status={review.get('status')} score={review.get('score')}")
        
        # Fix loop
        iteration = 0
        while review.get("status") == "needs_changes" and iteration < max_fix_iterations:
            iteration += 1
            issues = review.get("issues", [])
            if not issues:
                break
            # Prioritise HIGH, then MEDIUM — cap at 8 to avoid model timeouts on large batches
            high   = [i for i in issues if i.get("severity") == "high"]
            medium = [i for i in issues if i.get("severity") == "medium"]
            low    = [i for i in issues if i.get("severity") == "low"]
            priority_issues = (high + medium + low)[:8]
            self.log(f"[{name}] Fix iteration {iteration}/{max_fix_iterations}: {len(priority_issues)}/{len(issues)} issue(s) using {worker_name}")

            issues_text = "\n".join(f"  [{i['severity'].upper()}] {i['description']} → Fix: {i['fix']}" for i in priority_issues)
            fix_prompt = (
                f"You are the Worker AI. Fix the following issues in module: {name}\n\n"
                f"Issues to resolve:\n{issues_text}\n\n"
                "Apply all fixes now. Update the existing files in place using your Write/Edit tools."
            )
            
            fix_result = self._run_opencode(worker_model, fix_prompt, TIMEOUT_FIX)
            if not fix_result:
                return False
                
            review = self.executor_review(name, impl)
            self.log(f"[{name}] Re-review: status={review.get('status')} score={review.get('score')}")
            
        if review.get("status") == "approved" and review.get("score", 0) >= 95:
            return True
        return False

    def _process_one_module_with_fallback(self, module: dict, primary_name: str, primary_model: str, secondary_name: str, secondary_model: str, max_fix_iterations: int = 5) -> bool:
        """The 4-tier orchestrator for a single module with skip-on-block protection."""
        name = module['name']
        self.log(f"\n{'-'*60}\n[{name}] TIER 1: Using {primary_name} ({primary_model})\n{'-'*60}")
        if self._run_implement_and_fix(module, primary_name, primary_model, max_fix_iterations):
            return True
            
        self.log(f"[{name}] TIER 1 FAILED. Falling back to TIER 2: {secondary_name} ({secondary_model})...", "WARN")
        if self._run_implement_and_fix(module, secondary_name, secondary_model, max_fix_iterations):
            return True
            
        self.log(f"[{name}] TIER 2 FAILED. Falling back to TIER 3: EXECUTOR ({GEMINI_EXECUTOR})...", "WARN")
        if self._run_implement_and_fix(module, "Executor", GEMINI_EXECUTOR, max_fix_iterations):
            return True
            
        self.log(f"[{name}] TIER 3 FAILED. Falling back to TIER 4: SUPERVISOR ({SUPERVISOR_MODEL})...", "WARN")
        if self._run_implement_and_fix(module, "Supervisor", SUPERVISOR_MODEL, max_fix_iterations):
            return True

        # FIX: Skip-on-block protection.
        # After all 4 tiers fail, mark as skipped and continue rather than
        # hanging the entire pipeline on one module.
        self.log(f"[{name}] ALL TIERS FAILED. Module is blocked — skipping to unblock pipeline.", "ERROR")
        self.log(f"[{name}] SKIPPED_BLOCKED: Will be retried at end of build or by supervisor.", "WARN")
        return False

    # ── PRD excerpt helper ────────────────────────────────────────────────────

    def _prd_excerpt(self, module_name: str) -> str:
        keyword_map = {
            "auth":          ["JWT", "2FA", "TOTP", "login", "RBAC"],
            "database":      ["PostgreSQL", "Tables", "schema", "audit_log"],
            "lock":          ["Lock Request", "Verification Engine", "Server-Automated"],
            "emi":           ["EMI schedule", "payment", "overdue", "grace period"],
            "devices":       ["AMAPI", "Device Owner", "enrollment", "IMEI"],
            "decoupling":    ["Decoupling", "5-day", "RTOC", "PADT"],
            "paut":          ["PAUT", "offline", "Pre-Authorized"],
            "user-app":      ["User EMI App", "Kotlin", "lock state", "overlay"],
            "dealer-app":    ["Dealer App", "Flutter", "enrollment flow"],
            "reseller":      ["Reseller", "key request", "quota"],
            "admin":         ["Admin Panel", "admin", "audit log"],
            "fraud":         ["Play Integrity", "anomaly", "NEIR", "fraud"],
            "notifications": ["FCM", "push", "notification", "SMS"],
            "location":      ["GPS", "geofence", "location"],
            "keys":          ["key", "HMAC", "activation", "lifecycle"],
            "security":      ["certificate pinning", "command signing", "HSM", "Layer"],
        }
        relevant_keywords = []
        for key, kws in keyword_map.items():
            if key in module_name.lower():
                relevant_keywords.extend(kws)

        if not relevant_keywords:
            return self.prd_content[:4000]

        lines = self.prd_content.split("\n")
        relevant_lines = []
        for i, line in enumerate(lines):
            if any(kw.lower() in line.lower() for kw in relevant_keywords):
                start = max(0, i - 2)
                end   = min(len(lines), i + 5)
                relevant_lines.extend(lines[start:end])
                relevant_lines.append("---")

        excerpt = "\n".join(relevant_lines[:200])
        return excerpt if excerpt else self.prd_content[:4000]

    # ── Main build loop ───────────────────────────────────────────────────────

    def build(self, only_phase: int = None, start_module: str = None, max_fix_iterations: int = 5):
        self.log("=" * 70)
        self.log("EMI LOCKER AUTONOMOUS BUILDER v2.0 (Dual-Worker Parallel Mode)")
        self.log(f"Executor   : {GEMINI_EXECUTOR}  (planning + review, headless)")
        self.log(f"Worker 1   : {WORKER_MODEL_1}  (primary parallel)")
        self.log(f"Worker 2   : {WORKER_MODEL_2}  (secondary parallel)")
        self.log(f"Supervisor : {PRIMARY_SUPERVISOR} (this context window)")
        self.log("=" * 70)

        # Clear stale paused_at so the monitor shows the builder as active
        with self._state_lock:
            if "paused_at" in self.state:
                del self.state["paused_at"]
                self.state["started_at"] = datetime.now().isoformat()
            self._save_state()
            self.log("Cleared paused_at — build state reset to active.")

        self.start_supervisor_watcher()

        # Step 1: Executor reads PRD and confirms understanding
        plan_result = self.executor_build_plan()
        if not plan_result:
            self.log("EXECUTOR failed to read PRD. Continuing anyway.", "WARN")

        # Step 2: Filter modules
        modules = MODULES
        if only_phase:
            modules = [m for m in modules if m["phase"] == only_phase]
            self.log(f"Running Phase {only_phase} only — {len(modules)} modules")
        if start_module:
            names   = [m["name"] for m in modules]
            if start_module in names:
                idx     = names.index(start_module)
                modules = modules[idx:]
                self.log(f"Resuming from module: {start_module}")

        pending_modules = []
        with self._state_lock:
            completed_set = set(self.state.get("completed", []))
            
        for module in modules:
            if module["name"] in completed_set:
                self.log(f"Skipping {module['name']} (already completed)")
            else:
                pending_modules.append(module)

        total = len(pending_modules)
        self.log(f"Modules to build: {total}\n")
        
        if total == 0:
            self._print_final_summary()
            return

        # Split into two queues for parallel processing
        w1_queue = [m for i, m in enumerate(pending_modules) if i % 2 == 0]
        w2_queue = [m for i, m in enumerate(pending_modules) if i % 2 == 1]

        def worker_thread(queue, primary_name, primary_model, secondary_name, secondary_model):
            for module in queue:
                success = self._process_one_module_with_fallback(
                    module, primary_name, primary_model, secondary_name, secondary_model, max_fix_iterations
                )
                
                with self._state_lock:
                    if success:
                        self.log(f"APPROVED: {module['name']}")
                        self.state.setdefault("completed", []).append(module['name'])
                        if module['name'] in self.state.get("failed", []):
                            self.state["failed"].remove(module['name'])
                    else:
                        self.log(f"NEEDS WORK: {module['name']} — review manually", "WARN")
                        if module['name'] not in self.state.setdefault("failed", []):
                            self.state["failed"].append(module['name'])
                    self._save_state()
                time.sleep(2)

        # Run parallel threads
        with ThreadPoolExecutor(max_workers=2) as executor:
            future1 = executor.submit(worker_thread, w1_queue, "WORKER 1", WORKER_MODEL_1, "WORKER 2", WORKER_MODEL_2)
            future2 = executor.submit(worker_thread, w2_queue, "WORKER 2", WORKER_MODEL_2, "WORKER 1", WORKER_MODEL_1)
            future1.result()
            future2.result()

        self._print_final_summary()

    def _print_final_summary(self):
        with self._state_lock:
            completed = self.state.get("completed", [])
            failed    = self.state.get("failed", [])
        self.log("\n" + "=" * 70)
        self.log("BUILD COMPLETE")
        self.log(f"  Completed : {len(completed)}")
        self.log(f"  Failed    : {len(failed)} — {failed if failed else 'none'}")
        self.log(f"  Output    : {self.project_dir}")
        self.log(f"  Log       : {self.log_file}")
        self.log("=" * 70)
        self.log("")
        self.log("NEXT STEP (per PRD): Test Phase 1 on Xiaomi, Oppo, Vivo, Samsung")
        self.log("DO NOT proceed to Phase 2 until Phase 1 passes all OEM tests.")

        # Write completion flag — triggers Antigravity audit hook
        flag_file = self.project_dir / "BUILD_COMPLETE.flag"
        flag_file.write_text(
            f"phase=1\ncompleted={len(completed)}\nfailed={len(failed)}\n"
            f"timestamp={datetime.now().isoformat()}\n"
            f"modules={','.join(completed)}\n",
            encoding="utf-8",
        )
        self.log(f"Trigger flag written: {flag_file}")
        self.supervisor_final_audit(completed, failed)


def main():
    parser = argparse.ArgumentParser(description="EMI Locker Autonomous Builder v2.0")
    parser.add_argument("--phase",        type=int,  help="Build only this phase (1-5)")
    parser.add_argument("--start-module", type=str,  help="Resume from this module name")
    parser.add_argument("--mode",         type=str,  default="prototype", choices=["prototype", "production"], help="Build mode: prototype or production")
    parser.add_argument("--max-fixes",    type=int,  help="Max fix iterations per module (overrides mode defaults)")
    parser.add_argument("--project-dir",  type=str,  default=".", help="Project root directory")
    args = parser.parse_args()

    max_fixes = args.max_fixes if args.max_fixes is not None else (2 if args.mode == "prototype" else 5)

    builder = EmiLockerBuilder(project_dir=args.project_dir, mode=args.mode)
    builder.build(
        only_phase=args.phase,
        start_module=args.start_module,
        max_fix_iterations=max_fixes,
    )


if __name__ == "__main__":
    main()

