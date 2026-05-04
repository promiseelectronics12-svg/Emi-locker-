# EMI Locker Platform - Project Instructions

## Project Overview
EMI Locker is an MDM (Mobile Device Management) platform designed for mobile phone dealers and financial institutions in Bangladesh to manage devices sold on EMI. It uses Android Enterprise (AMAPI) to enforce system-level locks on non-payment.

## Core Mandates
- **NO HARDCODED DOMAINS**: All URLs must come from environment variables.
  - Backend: `API_BASE_URL` (default: `http://localhost:3000`)
  - Admin: `VITE_API_BASE_URL` (default: `http://localhost:3000`)
  - Flutter: Read from `.env` via `flutter_dotenv`, key: `API_BASE_URL`
  - Kotlin: Read from `BuildConfig`, key: `API_BASE_URL`
- **Security First**: 
  - Certificate pinning must be implemented and verified.
  - Command signing with HMAC-SHA256 is mandatory for all lock/unlock/decouple actions.
  - Play Integrity API must be used for device health checks.
- **Emergency Access**: Emergency calls (999, 112) must ALWAYS be available.

## Architecture
- **Backend**: Node.js + Express, PostgreSQL, Firebase Realtime DB, Firebase Cloud Messaging.
- **Admin Panel**: React (TypeScript) + Tailwind CSS + Vite.
- **User App**: Native Kotlin (Android) - Device Owner / DPC.
- **Dealer App**: Flutter (Android/iOS) - Management and Enrollment.

## Workflows
1. **Enrollment**: Dealer App generates QR -> User Setup Wizard scans -> User App installed as Device Owner -> Hardware info reported to Backend.
2. **Locking**: Dealer submits request -> Server verifies EMI status -> Approved -> FCM command sent -> User App enforces lock state.
3. **Decoupling**: Payment confirmed -> Admin executes decoupling -> RTOC generated -> App removes Device Owner and uninstalls.

## Key Files
- `backend/src/modules/devices/amapiService.js`: Core MDM integration.
- `user-app/app/src/main/java/com/emilocker/userapp/device/LockStateManager.kt`: Device-side enforcement.
- `dealer-app/lib/features/devices/enrollment_service.dart`: Enrollment logic.

## Deployment
- Use `.env.example` as a template for all environment variables.
- Document every URL variable with a comment: `# Replace with real domain before deploy`.
- Disable certificate pinning in dev if `API_BASE_URL` contains 'localhost'.
