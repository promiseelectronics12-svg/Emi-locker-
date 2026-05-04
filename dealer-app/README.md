# EMI Dealer & Reseller App

Flutter-based mobile application for EMI Locker Platform - Dealer and Reseller management.

## Features

### Dealer Features
- Device enrollment with QR code generation
- EMI schedule management
- Lock request submission (with server verification)
- Real-time device status monitoring via Firebase Realtime Database
- Payment tracking and recording
- Custom message delivery to devices
- Analytics dashboard with charts
- NEIR Export for BTRC compliance

### Reseller Features
- Dealer account management
- Activation key inventory
- Key sales to dealers
- Performance analytics

## Architecture

- **Role-based UI**: Single codebase with role switching (Dealer/Reseller)
- **State Management**: BLoC pattern for auth and business logic
- **API Client**: Dio-based HTTP client with certificate pinning
- **Real-time Updates**: Firebase Realtime Database integration
- **Security**: JWT tokens, biometric 2FA, secure storage

## Setup

1. Copy `.env.example` to `.env` and configure API URL:
   ```
   API_BASE_URL=http://10.0.2.2:3000  # Android emulator
   API_BASE_URL=http://localhost:3000  # iOS simulator
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_BASE_URL` | Backend API base URL | `http://localhost:3000` |

## Security

- Certificate pinning enabled for non-dev environments
- JWT tokens stored in Flutter Secure Storage
- Biometric authentication for 2FA
- All URLs read from environment variables

## Build

```bash
flutter build apk --release
flutter build ios --release
```