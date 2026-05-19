# EMI Locker Current Architecture And Superseded Plans

Status: Living product architecture record.

Last updated: 2026-05-19.

Purpose: keep the team aligned after multiple design changes. If an older Markdown file conflicts with this document, treat this document as the current product decision until the older file is updated.

## Current Product Philosophy

EMI Locker must be strict when risk appears, but quiet during normal daily use.

The user app should not behave like a heavy script that constantly scans, tracks, or uploads. The product direction is:

- lightweight on low-end and mid-budget Android phones
- adaptive instead of fixed-interval aggressive monitoring
- low server load
- low battery and heat impact
- visible in audit, quiet in daily use
- Device Owner / kiosk first, not removable overlay first
- backend is source of truth for commands, credit score, assignments, and audit

## Current Runtime Modes

| Mode | Meaning | Behavior |
| --- | --- | --- |
| Subconscious | Normal daily operation | Slow heartbeat, cheap signal checks, no constant GPS |
| Learning | First 15-30 days | Learn normal movement, charging, reboot, network, and SIM patterns |
| Alert | Risk score is rising | Faster checks, immediate important reports, possible SMS fallback |
| Locked / Fraud | Strong enforcement state | Kiosk lock, higher-priority location/SIM checks, capped reporting |
| Low Battery / Hot Device | Device protection state | Reduce non-critical GPS, sync, and background work |

Learning mode must never disable core security. SIM presence, Device Owner state, command acknowledgement, and basic heartbeat remain active.

## Heartbeat And Command Delivery

| Channel | Current decision |
| --- | --- |
| FCM | Primary instant lock/unlock/decouple command path |
| Internet heartbeat | Proof-of-life and state sync, not the main command path |
| Pending command fallback | Heartbeat should be able to pick up missed FCM commands |
| SMS heartbeat | Emergency fallback only, around once per 12-24 hours unless a critical SIM theft event occurs |

Production heartbeat should be adaptive (aligned with THREE_TIER_SERVICE_GUIDE.md):

- normal online active: 10-15 minutes
- stable/stationary: may stretch up to 20 minutes adaptively
- alert mode (overdue OR risk_score >= 3): 5 minutes
- lockdown pending: 3 minutes
- locked/fraud: 3 minutes, capped
- SMS: rare and cost-aware, emergency fallback only

## Lock Screen Direction

Current direction:

- one primary kiosk lock screen for real lock enforcement
- no removable watermark/overlay as the main enforcement path
- no old partial-lock ladder
- no Wi-Fi Settings shortcut inside lock task if it risks OEM Settings crashes
- payment/call/emergency/basic allowed actions can be exposed from the kiosk screen

The old overlay/watermark approach is superseded because users could disable overlay permission from the notification shade on some devices.

## Location Timeline

Current direction: phone-side intelligence, backend-side caps.

The user app should collect and filter meaningful locations locally. The backend should not receive raw GPS streams.

| Rule | Decision |
| --- | --- |
| Normal location storage | Rolling latest 24 meaningful points |
| Point 25 | Oldest point is removed; newest point enters the 24-point set |
| Raw GPS spam | Not allowed |
| Backend role | Verify signature, enforce caps, store limited timeline, audit access |
| Fraud/alert mode | May preserve more security evidence under a separate capped policy |

The timeline is not a normal log dump. It should represent meaningful places/routes such as home, work, shop, market, or unusual movement.

## Dealer History And Admin Access

Dealer app should show a local and server-backed device History tab for important events:

- SIM change or bound SIM missing
- tamper/protection degraded
- lock/unlock/decouple command result
- offline SMS heartbeat received
- unusual risk state

Phone number / SIM change history is permanent. Fraud/tamper history can be capped, for example latest 100 important events.

Full sensitive location timeline access should be controlled. Dealer can request location verification; admin/support reviews and approves according to policy.

## SIM Binding

Every financed device should bind to a registered SIM identity where practical.

Rules:

- at least one registered/bound SIM must remain present
- dual SIM is acceptable when the bound SIM is still present
- SIM missing triggers a time-escalating risk score contribution (see Risk Engine below) — never auto-locks alone
- if wrong SIM is inserted while bound SIM is missing, add risk weight
- persist `sim_missing_since` locally so reboot does not restart the timer
- send immediate signed alert/location when possible

SIM-change and phone-number-change records are important evidence and must not be removed by normal retention jobs.

## Risk Engine And Auto-Lock Rule

### Single Auto-Lock Rule (only rule — no alternative versions)

```
auto_lock = overdue_emi
         && risk_score >= 6
         && dealer_notification_window_expired  (minimum 2h grace)
```

Single tamper signal = dealer notification only, never lock.

### Signal Weights (time-escalating)

| Signal | Weight |
|--------|--------|
| EMI Locker admin revoked | 3 |
| SIM missing < 5 min | 0 |
| SIM missing < 2h | 4 |
| SIM missing < 24h | 6 |
| SIM missing >= 24h | 8 |
| Heartbeat lost (normal mode) | 4 → 6 at 24h → 8 at 48h |
| Gmail mismatch on EMI Locker | 2 |
| Boot after forced shutdown | 1 |

### Heartbeat State Machine

| State | Trigger | Heartbeat tolerance |
|-------|---------|---------------------|
| normal | default | 24h |
| alert | overdue OR risk_score >= 3 | 12h |
| lockdown_pending | auto_lock condition met | 6h |

### Power-Off Prevention (best-effort)

`DISALLOW_POWER_OFF` + `DISALLOW_SAFE_BOOT` applied via Device Owner. OEM-dependent — MIUI, ColorOS, FuntouchOS, OneUI may override power menu. Never promise guaranteed power-off block in contracts or marketing. Shutdown receiver uses `lastLocation` (cached) not live GPS fix.

## Re-Enroll, Recovery, And Resale

One physical phone can have multiple ownership periods. This must not mix customer data.

Current architectural direction:

- `devices` = physical hardware record
- `device_assignments` = customer/contract ownership period
- history, timeline, SIM events, EMI state, and lock state should be scoped to assignment where relevant

Re-enroll has two paths:

| Path | Use case | Data behavior |
| --- | --- | --- |
| Reconnect / Recovery | Same customer, same contract after reset/repair/reinstall | Continue old assignment/history |
| Resale / Clean Sheet | Dealer bought/took back phone and will sell to new customer | Admin approval required; old assignment archived/hidden from normal dealer view; new assignment starts clean |

Do not build resale/clean-sheet UI until assignment separation is designed.

## Credit Score

Credit score should be minimal and privacy-safe.

Store:

- HMAC of normalized NID, not plain SHA-256
- encrypted name if needed
- score band: Good, Watch, High Risk, New Customer
- score version/update time

Do not show detailed payment/location/SIM history to dealers as part of score lookup.

NID hash rule:

```text
nid_lookup = HMAC-SHA256(platform_secret, normalized_nid)
```

## Dealer Account And Invite Flow

Public dealer signup is not the desired production flow.

Current desired flow:

1. Admin/reseller creates invite.
2. Invite is sent to dealer Gmail.
3. Dealer installs dealer app.
4. Invite deep link opens dealer app.
5. Account creation screen appears only through the invite.
6. Invited email is locked.
7. Dealer sets password, backup phone, and profile.
8. Backend verifies one-time invite token and activates/pends the account.

Invite tokens must be server-side, one-time, hashed at rest, bound to email/role/reseller, and expire in about 24-48 hours.

## Backup Model

Backend database and company-controlled encrypted backups are source of truth.

Google-linked dealer backup is optional and should be treated as dealer workspace recovery only, not the main company disaster-recovery system.

Recommended backup layers:

- Neon / database point-in-time restore
- encrypted database export to company-controlled storage
- optional encrypted dealer local history backup

## Superseded Plans

The following older plans are no longer current:

| Old plan | Current decision |
| --- | --- |
| `PARTIAL_LOCK` as a separate runtime state | Removed; use reminder/history state or full kiosk lock rules |
| Removable watermark overlay as reminder enforcement | Superseded; kiosk screen is the primary lock path |
| Wi-Fi Settings shortcut inside lock task | Superseded after OEM Settings crash risk |
| Raw/continuous GPS logging | Superseded; use phone-side meaningful timeline filtering |
| Dealer Google account as company backup backbone | Superseded; use company-controlled encrypted backup |
| Plain SHA-256 NID lookup | Superseded; use HMAC-SHA256 with platform secret |
| Public dealer self-signup | Superseded; use invite-only onboarding |
| "SIM missing 5 minutes = auto-lock" | Superseded; SIM missing contributes time-escalating risk score only; lock requires overdue_emi && risk_score >= 6 && dealer window |
| VIP tier | Removed; two tiers only: Standard and Premium |
| "Disguised / decoy / fake" framing for enforcement app | Superseded; use DeviceProtectionService with honest enrollment disclosure |

## Next Foundation Work

Priority order before adding more UI:

1. Design `device_assignments` schema and migration path.
2. Persist SIM missing timer across reboot.
3. Add permanent SIM/phone history policy.
4. Upgrade NID lookup to HMAC-based design.
5. Add invite-token table and one-time invite enforcement.
6. Define learning-mode signals and thresholds.
7. Add heartbeat pending-command fallback.
