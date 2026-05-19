# Session Break State
**Paused at:** 2026-05-03 17:00 (BD time)

> Historical note, 2026-05-18: this file is an old break-state snapshot. The early enforcement-layer design concepts below were reconsidered. Current architecture uses `DeviceProtectionService` (honest, disclosed Device Owner enforcement) + `EMI Locker` (visible Customer Protection Layer). No deceptive framing, no disguised UI. Current decisions are documented in `docs/CURRENT_ARCHITECTURE_AND_SUPERSEDED_PLANS.md`.

---

## What Was Running
- **Autonomous Builder & Monitor** — Stopped cleanly. No background Node or Python processes are currently running.

---

## Architectural Decisions Finalized (This Session)
We made massive, enterprise-grade updates to the Master PRD (`EMI_Locker_PRD_v3.txt`). When we resume, the builder will strictly follow these rules:

### 1. SUPERSEDED — Early Enforcement App Design
- **Original approach:** Enforcement app had no visible icon post-setup. Reconsidered and replaced.
- **Current approach:** `DeviceProtectionService` (package `com.emilocker.protection`) — hidden launcher post-enrollment, Device Owner, disclosed at enrollment with line: "A background protection service remains installed to enforce the EMI agreement."
- **Battery Immunity:** App grants itself `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` via Device Owner privileges to prevent OEM firmware (MIUI, ColorOS) from sleeping the service.

### 2. SUPERSEDED — Zero-Touch Hardware Binding
- **No Manual Typing:** The app uses `TelephonyManager` and `WifiManager` (via Device Owner powers) to auto-fetch **IMEI 1, IMEI 2, MAC Address, and SoC info** at enrollment.
- **Current approach:** IMEI fetched via AIDL from DeviceProtectionService to EMI Locker customer app for Google Sign-In + IMEI auth flow.

### 3. PARTIALLY SUPERSEDED — Watchdog & Offline Fallback
- **SIM Swap SMS Fallback:** If SIM changes while offline, DeviceProtectionService uses `SmsManager` to fire a signed alert SMS to the dealer.
- **Dealer App:** Receives the alert, uploads new phone number to server.
- **Location Watchdog:** App tracks and alerts dealer if device moves unusually far.
- **USB/ADB Tamper Alerts:** App alerts dealer if Developer Options or PC connection is attempted.

### 4. PARTIALLY SUPERSEDED — KYC / NID Verification (Porichoy API)
- **No Photo Storage:** To avoid data privacy liability, we do NOT store photos of NID or user.
- **Porichoy Verification:** The Dealer App has an optional **"Verify NID (Cost: 10 BDT)"** button. Backend calls the Bangladesh Govt `porichoy.gov.bd` API to verify NID number and DOB instantly.

---

## What to Do When We Resume
1. Review this break state to refresh our memory.
2. Restart the Node Monitor (`cd monitor && node server.js`).
3. Restart the Autonomous Builder (`run_autonomous_build.bat`).
4. Watch the Gemini CLI Executor and Mimo Supervisor chew through the rest of Phase 3 (User App) and Phase 4 (Dealer App) using our newly perfected PRD!

---

## No Action Needed Right Now
Everything is paused safely. The PRD is fully updated. Take your break!
