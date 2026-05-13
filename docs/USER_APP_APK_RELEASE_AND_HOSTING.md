# User App APK Release And Hosting

Last verified: 2026-05-14

## Current Release

- App: EMI Locker User App
- Package: `com.android.simtoolkit`
- Version: `1.0.0`
- Version code: `1`
- Build type: signed, minified release APK
- APK size: `4,998,240` bytes
- Signing certificate SHA-256: `571b0a553b2b99e12af5485b2e6256eb3878b060cc4446fd827734489b4f6cc6`
- APK SHA-256: `547c6271503ef45b68b9c12ff076738f608f65ae8cbf60290fb2966c1255805d`
- Android provisioning package checksum: `VHxicVA-9FtoucEv8HZzj2CPZa6Mv2ApD7KWbBJVgF0`

## Local Private Signing Files

These files are intentionally local-only and must not be committed:

- `D:\EMI APP\user-app\keystore\emilocker-user-release.jks`
- `D:\EMI APP\user-app\keystore\release-signing.properties`

Both `D:\EMI APP\.gitignore` and `D:\EMI APP\user-app\.gitignore` ignore this keystore folder.

## GitHub Hosted APK

The APK is hosted on the dedicated `apk-releases` branch, separate from source code:

```text
https://raw.githubusercontent.com/promiseelectronics12-svg/Emi-locker-/apk-releases/user-app/1.0.0/emi-locker-user-1.0.0-release.apk
```

Metadata:

```text
https://raw.githubusercontent.com/promiseelectronics12-svg/Emi-locker-/apk-releases/user-app/1.0.0/metadata.json
```

This is acceptable for investor demos and controlled testing. For production, prefer a controlled HTTPS download host such as a backend static release endpoint, object storage, or CDN where we control availability, access logs, rollback, and cache headers.

## QR Provisioning Payload Shape

For self-hosted Device Owner provisioning, the QR code should include the package download URL and URL-safe Base64 SHA-256 package checksum:

```json
{
  "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME": "com.android.simtoolkit/com.android.simtoolkit.device.DeviceAdminReceiver",
  "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION": "https://raw.githubusercontent.com/promiseelectronics12-svg/Emi-locker-/apk-releases/user-app/1.0.0/emi-locker-user-1.0.0-release.apk",
  "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM": "VHxicVA-9FtoucEv8HZzj2CPZa6Mv2ApD7KWbBJVgF0",
  "android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED": true,
  "android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE": {
    "api_base_url": "https://emi-locker-erkt.onrender.com"
  }
}
```

The device must be factory-reset or in first setup flow for Device Owner QR provisioning. If the app is installed normally by ADB, it can be Device Admin, but not true Device Owner unless the device state allows `dpm set-device-owner` for testing.

## Verification Commands

```powershell
cd "D:\EMI APP\user-app"
.\gradlew.bat clean assembleRelease
.\gradlew.bat lintRelease
& "E:\Android\Sdk\build-tools\36.1.0\apksigner.bat" verify --verbose --print-certs app\build\outputs\apk\release\app-release.apk
```

## Current Verification Result

- `assembleRelease`: passed
- `lintRelease`: passed
- APK signature verification: passed with APK Signature Scheme v2
- Compiled manifest includes Android 12+ provisioning callbacks:
  `GET_PROVISIONING_MODE` and `ADMIN_POLICY_COMPLIANCE`
- Retrofit base URL is normalized with a trailing slash before API creation
- GitHub raw APK URL: HTTP 200
