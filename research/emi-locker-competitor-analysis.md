# EMI Locker Competitor APK Inspection

Date: 2026-05-13

Scope: clean-room inspection of APKs pulled from the connected test device and APK files present in the device Downloads folder. This report records package metadata, permissions, manifest-level control evidence, and high-level product conclusions only. It does not copy proprietary implementation code.

## APKs Inspected

| APK | Package | Label | Category Found |
| --- | --- | --- | --- |
| `PalmPay-v1.6.6.apk` / `com.bengal.palmpay.bd-base.apk` | `com.bengal.palmpay.bd` | PalmPay | Payment/customer app with overlay, location, boot receiver |
| `apptwo.credlockng.com-base.apk` | `apptwo.credlockng.com` | Credlock FoneFlex | Customer/finance app, not a hard lock controller by manifest evidence |
| `com.dealer.safetylockerpro-base.apk` | `com.dealer.safetylockerpro` | Safety Locker Pro | Dealer/retailer app, not a hard lock controller by manifest evidence |
| `HT-v6.apk` | `com.htlocker.retailer` | HT Locker | Dealer/retailer app, not a hard lock controller by manifest evidence |
| `Google-DeviceLockController.apk` | `com.google.android.apps.devicelock` | Device Lock Controller | Real Android device-admin/device-lock controller |
| `download-app-release.apk` | `it.vfsfitvnm.vimusic` | ViMusic | Irrelevant music app |
| `download9811.apk` | not readable | not readable | Corrupt/invalid APK manifest |

## Key Manifest Evidence

| App | Device Admin | Overlay | Boot Receiver | Location | Query All Packages | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Google Device Lock Controller | Yes | No | Yes | No | Yes | Declares `BIND_DEVICE_ADMIN`, `android.app.device_admin`, `DlcDeviceAdminReceiver`, `LOCKED_BOOT_COMPLETED`, and `DEVICE_ADMIN_SERVICE`. |
| PalmPay | No | Yes | Yes | Yes | No | Looks like payment/reminder/overlay app. No manifest evidence that it is the strong enforcement engine. |
| Credlock FoneFlex | No | No | No | Yes | No | Finance/customer app pattern. No device-owner or device-admin manifest evidence. |
| Safety Locker Pro | No | No | Yes | No | No | Dealer/retailer app pattern. Boot receiver and FCM, but no hard enforcement manifest evidence. |
| HT Locker | No | No | No | No | No | Retailer-facing app pattern. Camera/notification/FCM/media permissions. |

## Important Finding

The strongest APK in this set is Google Device Lock Controller, not PalmPay, Credlock, Safety Locker Pro, or HT Locker.

PalmPay appears to be a payment/customer experience app. If a Tecno phone blocks developer options, USB behavior, factory reset paths, or uninstall/permission tampering, that control is probably coming from one of these:

- Device Owner / Android Enterprise policy
- Google Device Lock Controller or a similar device-lock DPC
- OEM/preloaded Transsion/Tecno financing agent
- A managed provisioning flow applied before customer handover

It is unlikely that the visible PalmPay APK alone is doing the whole “hard lock” job, because it does not declare device-admin/device-owner components in the manifest inspected here.

## Comparison To Our Path

Our user app has stronger enforcement intent than most public competitor/customer APKs inspected here:

- It declares a device admin receiver.
- It has overlay support.
- It has boot handling.
- It has foreground service support.
- It is designed to receive backend commands and apply lock state.

But the decisive difference is not only code. The device must actually be provisioned as Device Owner / fully managed. Without Device Owner, the app remains exposed to normal Android user controls such as Settings > Apps > Permissions, force stop, uninstall paths, and OEM battery restrictions.

## What This Means For Strategy

Our direction is correct: Android Enterprise Device Owner / AMAPI is the right category for a serious EMI-lock product.

We should not try to beat competitors with a pure Play Store app or only overlay/device-admin tricks. That category is too weak. The production route should be:

1. Dealer creates enrollment.
2. Backend creates AMAPI enrollment token.
3. Fresh/factory-reset device scans the QR from setup wizard.
4. Device becomes fully managed / Device Owner before customer receives it.
5. Lock, unlock, app visibility, permission policy, USB/debugging policy, and factory-reset protections are enforced through managed policy.
6. Our app reports health, online/offline state, lock state, permission state, and location as the business agent.

## What To Install Next

For useful research, install only apps that represent different categories:

- Google Device Lock Controller: keep as the benchmark for true lock-controller behavior.
- PalmPay: keep as the benchmark for payment/customer flow and visible payment UX.
- Credlock FoneFlex: keep as finance/customer app reference only.
- Safety Locker Pro / HT Locker: keep as dealer-app references only.

Avoid installing apps that request unrelated personal data access unless we are deliberately reviewing privacy risk. Those do not help us build a cleaner product.

## Next Engineering Checks

1. Confirm Device Owner state on our test user device:
   `adb shell dpm get-device-owner`

2. Confirm installed permissions for our user app:
   `adb shell dumpsys package com.android.simtoolkit`

3. Confirm policy status in-app:
   `DevicePolicyManager.isDeviceOwnerApp(packageName)`

4. Fix manifest/build mismatch if source permissions are not present in the installed APK.

5. Add a dealer-visible “management strength” status:
   - Device Owner active
   - Device Admin active
   - Overlay active
   - Notification permission active
   - Location permission active
   - Background location active
   - Battery optimization exempt
   - Last heartbeat
   - Last lock-state sync

## Bottom Line

The competitor behavior the user observed is probably not app-only. It is almost certainly a managed-device/OEM-preload style system. Our project is already aiming at the right production-grade path, but we must make Device Owner provisioning the first-class installation path and treat normal sideload/admin/overlay mode as testing or fallback only.
