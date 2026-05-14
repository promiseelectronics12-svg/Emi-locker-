# EMI Locker Fault Ledger

This file records failures, false fixes, and lessons learned. Keep it factual. A fault is not shame; it is system memory.

## Status Labels

| Label | Meaning |
| --- | --- |
| Open | Known issue, not fixed |
| Mitigated | Workaround exists but not fully solved |
| Fixed | Code/schema/config changed and verified |
| Needs field test | Built but not physically verified |
| Won't fix now | Accepted limitation for current stage |

## Fault Records

| ID | Date | Area | Fault | Root cause | Fix / prevention | Status |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | 2026-05-11 | Location | Pull location accepted but dealer did not reliably show live result | Multi-hop flow had route/payload/auth mismatches and weak UI confirmation | Route contract documented; map UI must show fresh vs previous location | Needs field test |
| F-002 | 2026-05-11 | Location | Multiple pull requests could pile up | Dealer repeated taps and backend allowed pending buildup | One active pull per device, expire old pulls, dealer cooldown | Needs field test |
| F-003 | 2026-05-11 | User app auth | Location report skipped when local device token missing | Older enrollment did not return `device_token` | Added refresh-token flow and auto refresh | Needs field test |
| F-004 | 2026-05-11 | FCM | `GET_LOCATION` rejected by user app command verification | Server/device HMAC schemes did not match | Skip HMAC for GET_LOCATION while using device-token for report | Fixed |
| F-005 | 2026-05-11 | FCM | Background data command did not reach service reliably | Payload included notification block for data-only command | Remove Android notification block from data commands | Fixed |
| F-006 | 2026-05-11 | Dealer UI | Lock request spinner could run indefinitely | Action had no screen-level timeout or confirmation fallback | Add action-level timeout and pending state | Open |
| F-007 | 2026-05-11 | Dealer UI | Errors hidden from user | Silent `catch (_)` blocks | Replace with logging and readable fallback messages | Open |
| F-008 | 2026-05-11 | Dealer codebase | `emi_locker_app.dart` too large | Many features inside one file | Split by feature after stabilization | Open |
| F-009 | 2026-05-11 | Device health | Dealer might show stale previous location as current | No clear freshness model in UI | Show timestamp/freshness and stale warning | Needs field test |
| F-010 | 2026-05-11 | Permissions | User can disable overlay/SMS/notification permissions in settings | Android allows permission changes unless device owner/profile owner policies enforce more | User app reports permission health on app start/resume/FCM/service/heartbeat; backend emits `device_health_changed`; dealer shows protection degraded | Mitigated |
| F-011 | 2026-05-11 | Evidence vault | Private image storage could become server burden | Raw photos should not live unprotected in backend DB | Store encrypted evidence in dealer-linked vault and keep metadata only | Needs field test |
| F-012 | 2026-05-11 | QR enrollment | Blank QR if AMAPI enterprise env missing | Backend dependency not configured, Flutter swallowed error | Surface readable setup error and document required env | Needs field test |
| F-013 | 2026-05-12 | Enrollment IMEI | User app cannot reliably read IMEI on modern Android | Android restricts IMEI access for normal apps from Android 10+ | Dealer app now scans box/sticker QR or barcode, extracts valid Luhn IMEIs only, and backend validates IMEI checksum/deduplication | Needs field test |
| F-014 | 2026-05-12 | User app setup | App repeatedly opened/closed after activation or settings changes | Auth setup flow auto-launched the next Android permission/settings screen on resume and from activity-result callbacks | Permission setup now performs only one user-triggered action at a time; returning from Settings no longer auto-opens another screen | Needs field test |

## Fault Entry Template

| ID | Date | Area | Fault | Root cause | Fix / prevention | Status |
| --- | --- | --- | --- | --- | --- | --- |
| F-NEW | YYYY-MM-DD | Area | What failed | Why it failed | What changed or should change | Open |
