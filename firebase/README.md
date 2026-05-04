# EMI Locker Firebase Configuration

Firebase project configuration for the EMI Locker Platform.

## Overview

This directory contains Firebase configuration for:
- **Cloud Messaging (FCM)** - Push notifications for devices and apps
- **Firebase Auth** - Authentication (if used)
- **Firebase Analytics** - Usage tracking

## Configuration Files

### `google-services.json.example`
Copy to appropriate app directories:
- `user-app/google-services.json` - User Android app
- `dealer-app/google-services.json` - Dealer Flutter app
- `admin-panel/google-services.json` - Admin React app (if using Firebase Auth)

### `firebase-messaging-sw.js.example`
Service worker for handling push notifications in web apps.

## Setup Instructions

1. Create a Firebase project at https://console.firebase.google.com
2. Add Android app with package name `com.emilocker.user`
3. Add iOS app with bundle ID `com.emilocker.dealerapp`
4. Download `google-services.json` for each platform
5. Copy to respective app directories as `google-services.json`
6. Never commit these files to version control

## Firebase Services Used

| Service | Purpose |
|---------|---------|
| Cloud Messaging | Push notifications to devices and apps |
| Analytics | Usage tracking and crash reporting |
| Remote Config | Feature flags and dynamic configuration |

## Security Rules

See `rules/` directory for:
- Firestore security rules
- Realtime Database rules
- Storage rules

## Local Development

For local development, you can disable Firebase by:
1. Not adding `google-services.json`
2. Using mock/stub services in code

## Production Checklist

- [ ] Enable App Check for production
- [ ] Configure analytics data retention
- [ ] Set up monitoring alerts
- [ ] Review security rules
- [ ] Configure crash reporting

## Environment Variables

For backend Firebase Admin SDK, configure via environment variables:
- `FIREBASE_PROJECT_ID`
- `FIREBASE_PRIVATE_KEY`
- `FIREBASE_CLIENT_EMAIL`