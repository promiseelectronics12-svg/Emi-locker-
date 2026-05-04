# Session Break State
**Paused at:** 2026-05-03 17:00 (BD time)

---

## What Was Running
- **Autonomous Builder & Monitor** — Stopped cleanly. No background Node or Python processes are currently running.

---

## Architectural Decisions Finalized (This Session)
We made massive, enterprise-grade updates to the Master PRD (`EMI_Locker_PRD_v3.txt`). When we resume, the builder will strictly follow these rules:

### 1. Ultimate Stealth Mechanics (User App)
- **Package Name:** Changed to `com.android.system.stk.services` (disguised as SIM Toolkit to scare away hackers).
- **Setup UI:** The app will open as a fake "SIM Toolkit Configuration" screen. The dealer enters a hidden activation code, and the app permanently vanishes from the launcher.
- **Battery Immunity:** App will automatically grant itself `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` using Device Owner privileges to prevent Chinese firmware (MIUI, ColorOS) from sleeping the app.

### 2. Zero-Touch Hardware Binding
- **No Manual Typing:** The app will use `TelephonyManager` and `WifiManager` (via Device Owner powers) to silently and instantly auto-fetch **IMEI 1, IMEI 2, MAC Address, and SoC info**.

### 3. Watchdog & Offline Fallback
- **SIM Swap SMS Fallback:** If the SIM changes while offline, the User App uses `SmsManager` to fire a silent SMS (`EMILOCKER_ALERT...`) to the dealer.
- **Dealer App Interceptor:** The Flutter Dealer App will use the `RECEIVE_SMS` permission to silently catch that SMS and auto-upload the new phone number to the server, with zero manual work from the dealer.
- **Location Watchdog:** App will track and alert the dealer if the device moves unusually far.
- **USB/ADB Tamper Alerts:** App will alert the dealer if Developer Options or a PC connection is attempted.

### 4. KYC / NID Verification (Porichoy API)
- **No Photo Storage:** To avoid data privacy liability, we will NOT store photos of the NID or the user.
- **Porichoy Verification:** The Dealer App has an optional **"Verify NID (Cost: 10 BDT)"** button. When clicked, our backend calls the official Bangladesh Govt `porichoy.gov.bd` API to verify the NID number and DOB instantly.

---

## What to Do When We Resume
1. Review this break state to refresh our memory.
2. Restart the Node Monitor (`cd monitor && node server.js`).
3. Restart the Autonomous Builder (`run_autonomous_build.bat`).
4. Watch the Gemini CLI Executor and Mimo Supervisor chew through the rest of Phase 3 (User App) and Phase 4 (Dealer App) using our newly perfected PRD!

---

## No Action Needed Right Now
Everything is paused safely. The PRD is fully updated. Take your break!
