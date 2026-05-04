# EMI Locker User App

Android application for EMI Locker device management with Device Owner capabilities. This app implements the DPC (Device Policy Controller) for enterprise device management.

## Overview

The EMI Locker User App is an Android MDM (Mobile Device Management) application that:
- Enrolls as Device Owner via Android Management API
- Enforces EMI payment compliance by locking/unlocking device functionality
- Blocks developer options and USB debugging for security
- Integrates with BTRC NEIR for IMEI verification
- Manages work profiles and enforces FRP (Factory Reset Protection)

## Setup

```bash
# Install dependencies
./gradlew dependencies

# Copy environment template
cp .env.example .env

# Configure .env with real credentials before deploy

# Build debug APK
./gradlew assembleDebug

# Build release APK
./gradlew assembleRelease
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_BASE_URL` | Backend API URL | `http://localhost:3000` |
| `FLUTTER_ENV` | Environment | `development` |

**IMPORTANT**: When building for production, update `API_BASE_URL` with the real domain. Certificate pinning is automatically disabled when connecting to localhost.

## Project Structure

```
user-app/
├── app/
│   └── src/main/
│       ├── java/com/emilocker/app/
│       │   ├── config/         # App configuration and API client
│       │   ├── controllers/    # Business logic
│       │   ├── models/         # Data models
│       │   ├── services/       # API services
│       │   ├── utils/          # Utility classes
│       │   ├── workers/        # Background workers
│       │   └── receivers/      # Broadcast receivers
│       └── res/
│           ├── drawable/       # UI assets
│           ├── layout/         # XML layouts
│           ├── values/         # Strings, colors, themes
│           └── xml/            # Device policy configs
├── build.gradle
└── .env.example
```

## Architecture

Clean Architecture with MVVM pattern using:
- **Hilt** for dependency injection
- **Retrofit** for API communication
- **Coroutines** for async operations
- **ViewBinding** for UI

## Security Features

- Certificate pinning (automatically disabled on localhost for development)
- Biometric authentication required
- Secure storage for credentials using EncryptedSharedPreferences
- Device Policy Controller (DPC) for MDM capabilities
- USB data blocked when device is locked
- Developer options hidden after enrollment

## Build Variants

| Variant | Purpose | Signing |
|---------|---------|---------|
| Debug | Development testing | Debug keystore |
| Release | Production deployment | Release keystore |

## Device Owner Enrollment

The app uses Android's QR code enrollment mechanism:
1. Dealer generates enrollment QR code from dealer app
2. User taps screen 6 times during first boot to trigger enrollment
3. QR code is scanned and app is installed as Device Owner
4. Policies are applied immediately

## Important Notes

- The app requires Android 8.0 (API 26) or higher
- Device Owner privileges cannot be removed without factory reset
- All API calls use certificate pinning in production
- Firebase Cloud Messaging used for push notifications