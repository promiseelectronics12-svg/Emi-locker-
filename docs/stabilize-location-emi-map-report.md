# Stabilize Location, EMI Terms, Map UI, and Runtime Guardrails

## Summary

This change connects the dealer app, backend, and user app around one stable runtime contract:

- Dealer binding now captures full EMI terms.
- Backend stores EMI terms during pending enrollment and creates the active EMI schedule only after the user app confirms the binding code.
- User app stores finite local installment rows, preventing reminders after the EMI term ends.
- Pull Location now routes from FCM `GET_LOCATION` directly to an authenticated GPS report.
- Dealer app shows the reported location on Google Maps with a marker and accuracy circle.
- Dealer message sending no longer depends on Redis in the critical path.

## Backend Changes

- Added EMI term validation to dealer enrollment creation.
- Added pending enrollment EMI fields and promoted the Neon migration to main.
- Added a device-token protected EMI schedule endpoint at `/api/v1/device/emi-schedule`.
- Updated location reporting to accept `pull_id`, complete matching pull requests, update last known device location, prune old rows, and emit SSE location events.
- Relaxed registered dealer operational limits to duplicate/pending-request guardrails instead of Redis-blocking rate limits.

## App Changes

- Dealer app binding wizard now requires total price, down payment, monthly EMI, duration, first due date, and grace days.
- Dealer app Pull Location dialog now renders Google Maps, accuracy radius, timestamp, coordinates, and an external Google Maps action with a 10-second cooldown.
- User app saves schedule rows from binding confirmation and refreshes them from the backend on dashboard load.
- User app handles `GET_LOCATION` directly inside the FCM service to avoid the previous service-start breakpoint.

## Validation

- Backend JavaScript syntax checks passed.
- User app `:app:assembleDebug` passed.
- Dealer app debug APK was produced successfully.
- Flutter analyze still reports existing warnings in `emi_locker_app.dart`, but no blocking errors from this change.

## Deployment Notes

- Neon migration `121_enrollment_emi_terms.sql` has already been applied to the main Neon branch.
- Render must be redeployed before the new app builds can use the new backend contract.
- Dealer Android builds need a valid `GOOGLE_MAPS_API_KEY` Gradle property for production map rendering.
