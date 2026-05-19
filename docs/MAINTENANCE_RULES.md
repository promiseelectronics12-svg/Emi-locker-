# EMI Locker Maintenance Rules

These rules exist to stop invisible failures, infinite spinners, and route mismatch bugs from recurring.

Current architecture decisions and superseded plans are documented in `docs/CURRENT_ARCHITECTURE_AND_SUPERSEDED_PLANS.md`.

## Non-Negotiable Runtime Rules

1. No dealer action can spin forever.
2. Every backend command must return an accepted, failed, pending, or rejected state.
3. Every device command must have a result route or later status sync route.
4. Every FCM command must be traceable by command id or request id.
5. Every stale value shown in the dealer app must include timestamp/freshness.
6. Every catch block must log, show a user-safe message, or document why ignore is safe.
7. Every app permission required for protection must be included in QC tests.

## Dealer App Rules

| Rule | Reason |
| --- | --- |
| No feature file over 500 lines after refactor | Keeps flows understandable |
| No silent `catch (_) {}` | Prevents hidden failures |
| All command dialogs need timeout and fallback text | Prevents infinite loading |
| Use typed models for critical routes | Prevents response-shape confusion |
| SSE updates must refresh visible state and cached device state | Prevents stale UI |

## Backend Rules

| Rule | Reason |
| --- | --- |
| Registered dealer actions should not depend on Redis availability | Redis failure must not block normal operations |
| FCM invalid-token result must update device health | Dealer needs app removed/offline signal |
| One active pull-location request per device | Prevents DB clogging and queue confusion |
| Device-token protected routes must verify JWT consistently | Prevents auth scheme mismatch |
| Migrations must be documented in schema map | Keeps Neon aligned with code |

## User App Rules

| Rule | Reason |
| --- | --- |
| Adaptive heartbeat must report permission/SIM/lock health | Dealer must know when app is degraded without draining battery/server |
| Permission health changes must be reported immediately at the next app lifecycle/FCM/service touchpoint | Prevents silent permission tampering |
| Offline unlock must sync when device returns online | Dealer status must reflect real device state |
| Kiosk lock screen must relaunch or defend against dismissal where Android allows | Prevents easy bypass |
| SMS/offline OTP support must detect permission missing | Prevents silent OTP failure |
| Local EMI notices must come from finite schedule rows | Prevents stale due/payment messages after term ends |

## Release Checklist

Before every field build:

- Backend starts locally or passes syntax/build checks.
- Dealer app builds debug APK.
- User app builds debug APK.
- `docs/SYSTEM_MAP.md` updated if flow changed.
- `docs/API_ROUTE_INDEX.md` updated if route changed.
- `docs/FAULT_LEDGER.md` updated if bug/fix happened.
- QC workbook updated if new test scenario exists.
