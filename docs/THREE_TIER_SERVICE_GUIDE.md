# EMI Locker Service Tier Guide

Status: Locked — two tiers only. VIP removed 2026-05-19 by product decision.

Important: older reminder, disturbance, partial-lock, and watermark language is superseded by `docs/CURRENT_ARCHITECTURE_AND_SUPERSEDED_PLANS.md`. Current enforcement direction is adaptive monitoring plus one primary kiosk lock screen.

Purpose: keep every developer, AI model, tester, and business operator aligned on what `standard` and `premium` mean. A tier must never be treated as a cosmetic label only. It changes backend policy, dealer workflow, customer push behavior, and support expectations.

## Naming Rule

| Internal value | Public label | Meaning |
| --- | --- | --- |
| `standard` | Standard | Manual dealer-controlled EMI protection, no customer push |
| `premium` | Premium | Backend-assisted automation with dealer control, customer push included |

Use the internal values in code and database. Use the public labels in dealer/customer UI.

## Product Principle

EMI Locker must protect both parties:

- Dealer protection: collateral cannot disappear silently, payment default must be visible, lock/unlock must be auditable.
- Customer dignity: customer must understand due dates, payment status, grace period, support path, and why any restriction is applied.
- Enforcement ladder: notify first, explain clearly, then apply kiosk/full lock only when business rules justify it.

The product should not feel like punishment by default. It should feel like a structured EMI assistant that becomes strict only when rules are broken.

## Tier Summary

| Tier | Target client | Payment handling | Lock behavior | Customer push | Dealer push |
| --- | --- | --- | --- | --- | --- |
| Standard | Small shops, manual dealers | Dealer handles payments outside system | Same enforcement rule as Premium: auto-lock on `overdue_emi && risk_score >= 6 && dealer_window_expired`; dealer also has manual lock/unlock | None | All safety alerts |
| Premium | Serious dealers wanting automation | Dealer records/confirms payment | Backend assists with due-state alerts and lock rules; dealer unlocks/confirms | Payment confirmed, overdue reminders, advance payment | All safety alerts |

## Push Notification Split (locked)

Dealer safety alerts fire for both tiers. Customer push is Premium-only.

| Event | Customer push | Dealer push |
|-------|--------------|-------------|
| Payment confirmed | Premium only | Both tiers |
| Overdue reminder (5-day) | Premium only | Both tiers |
| Advance payment alert | Premium only | Both tiers |
| SIM removed | None | Both tiers |
| Device locked | None | Both tiers |
| App tamper (EMI Locker admin revoked) | None | Both tiers |
| Shutdown detected | None | Both tiers |
| App removal suspected | None | Both tiers |

## Standard Tier

### Business Promise

Standard is the low-cost, dealer-operated tier. The platform gives the dealer the tools, but the dealer makes all decisions.

### Backend Behavior

- Store device as `service_tier = 'standard'`.
- Create and store EMI schedule during confirmed enrollment.
- Send overdue notifications to dealer.
- Apply same auto-lock rule as Premium: `overdue_emi && risk_score >= 6 && dealer_notification_window_expired`. Enforcement is not tier-dependent — only customer push is.
- Single tamper signal → dealer notification only, never auto-lock.
- Allow dealer-triggered lock/unlock if ownership and device policy are valid.
- Store all lock/unlock commands and device confirmations.
- Keep heartbeat, online/offline, permission health, FCM token state, and last known location.
- Send dealer FCM for all safety alert events (SIM removed, lock, tamper, shutdown, app removal).

### Dealer App Behavior

- Show key as `Standard`.
- Explain: "Manual payment tracking. Dealer receives overdue alerts and controls lock/unlock."
- Device detail must show:
  - EMI term summary
  - Due date
  - Last payment marker if entered
  - Lock state
  - Last heartbeat/online status
  - Manual lock/unlock buttons
- No infinite spinner. Every action must show `accepted`, `waiting for device`, `applied`, `failed`, or `expired`.

### DeviceProtectionService Behavior

- Core enforcement agent.
- Applies manual lock/unlock commands from backend.
- Reports heartbeat, lock state, permission health, location result, and offline unlock state.

### EMI Locker Customer App Behavior

- Shows basic EMI status and dealer contact.
- No push notifications for Standard.
- Device Admin status monitored; revocation reported to backend as risk signal.

## Premium Tier

### Business Promise

Premium reduces dealer workload. The backend watches EMI dates and applies rules automatically, but the dealer still controls payment confirmation and final unlock decisions.

### Backend Behavior

- Store device/schedule as `service_tier = 'premium'`.
- Run scheduler rules:
  - 5 days before due date: customer + dealer notification.
  - Due date: payment due alert to dealer.
  - After grace period: lock eligibility / risk state.
  - Combined risk (overdue_emi && risk_score >= 6 && dealer window expired): full kiosk lock.
- Payment can be recorded by dealer/admin.
- Unlock requires dealer/admin action, except temporary grace unlock.
- Do not let unlock bypass payment/business rules.
- Emit SSE to dealer for due alerts, auto-lock, payment recorded, unlock, heartbeat changes, permission degradation.
- Send customer FCM: payment confirmed, overdue reminders, advance payment alerts.

### Dealer App Behavior

- Show key as `Premium`.
- Explain: "Automatic due-state alerts and overdue lock rules. Dealer confirms payment and unlocks."
- Device detail must show:
  - Next due date
  - Grace period
  - Automation status
  - Overdue days
  - Risk score (informational)
  - Payment recorded count
  - Manual payment record/confirm action
  - Unlock/grace action
- Dealer should see automation timeline:
  - Due alert sent
  - Warning/risk state recorded
  - Full lock applied
  - Device confirmed state

### DeviceProtectionService Behavior

- Core enforcement agent.
- Applies backend automation commands.
- Reports applied state through heartbeat or command-result route.
- Offline unlock/grace flow must remain available for field rescue.

### EMI Locker Customer App Behavior

- Shows EMI schedule, installments left, due date, grace period.
- Receives push: payment confirmed, overdue reminder, advance payment.
- Shows payment recorded message and lock reason when applicable.
- Shows dealer contact.
- Device Admin status monitored; revocation reported as risk signal.

## Backend Data Model Required

Minimum fields to verify/add:

| Entity | Field | Purpose |
| --- | --- | --- |
| `devices` or `emi_schedules` | `service_tier` | Runtime policy tier: `standard`, `premium` |
| `activation_keys` | `tier` | Stock/inventory key tier — DROP `vip` enum value |
| `enrollments` | `tier` | Pending enrollment selected tier |
| `emi_schedules` | `service_tier` | Preferred place if tier is tied to agreement |
| `emi_payments` | normalized status fields | One canonical payment state |
| `payment_events` | event log | Idempotent confirmation history |
| `device_commands` | command lifecycle | `created`, `sent`, `received`, `applied`, `failed`, `expired` |

Rule: key tier must be copied into confirmed device/schedule tier during `confirmFromDevice()`.

## Backend Tier Policy Matrix

| Capability | Standard | Premium |
| --- | --- | --- |
| EMI schedule stored | Yes | Yes |
| Dealer overdue notification | Yes | Yes |
| Customer push (payment/overdue/advance) | No | Yes |
| Auto-lock scheduler | Yes — same rule as Premium | Yes — `overdue_emi && risk_score >= 6 && dealer_window_expired` |
| Dealer manual lock | Yes | Yes |
| Dealer manual unlock | Yes | Yes |
| Advance payment | No | Yes |
| Settlement tracking | No | Optional |

## Heartbeat And Backend Noise

Heartbeat is necessary but must be controlled.

### Recommended Heartbeat Policy

Baseline: **10-15 minutes** in normal mode. Adaptive — stretch longer when device is stationary/healthy, shorten when risk or lock state is active. Backend command fallback must accept up to 15-minute gap in normal mode; do not design the pending-command fallback to require sub-5-minute heartbeats.

| Situation | Frequency |
| --- | --- |
| Healthy online, stationary | 15 minutes (may stretch up to 20 minutes adaptively) |
| Healthy online, active | 10 minutes |
| Device recently locked/unlocked | Immediately once, then return to normal |
| Alert mode (overdue OR risk_score >= 3) | 5 minutes |
| Permission degraded | Report at first touchpoint, repeat every 5 minutes until resolved |
| Lockdown pending (risk_score >= 6 + overdue) | 3 minutes |
| Location pull | Only when requested |
| FCM token changed | Immediately |
| App start/service restart | Immediately |

Do not use a flat 60-minute heartbeat as the normal baseline — this creates unacceptable delay for pending-command fallback and risk score recalculation.

## Implementation Plan

### Step 1: Backend Source Of Truth

- Add `service_tier` to active schedule or device runtime model.
- Copy enrollment/key tier into active schedule/device during confirmation.
- Expose tier in dealer device list, lock detail, user schedule refresh, heartbeat response.

### Step 2: Tier-Aware Scheduler

- Change auto-lock scheduler:
  - `standard`: same risk-engine auto-lock rule as Premium (`overdue_emi && risk_score >= 6 && dealer_window_expired`); no customer push; dealer also retains manual lock/unlock.
  - `premium`: same lock rule + customer push (overdue reminders, payment confirmed, advance alerts).

### Step 3: Payment Ledger Cleanup

- Pick one canonical payment table/route set.
- Normalize `status` vs `payment_status`.
- Add payment event idempotency.

### Step 4: Dealer App Tier Explanation

- In key purchase/selection UI, show a tier detail sheet.
- In enrollment wizard, show selected tier behavior.
- In device detail, show tier badge and tier-specific actions.

### Step 5: DeviceProtectionService Tier Behavior

- Reads tier from backend.
- Standard: basic schedule/lock support.
- Premium: automation explanation and richer schedule display.

## Developer Rule

Any code that reads `tier` must answer:

"Is this tier an inventory tier, a customer credit tier, or a service behavior tier?"

Do not mix them.

- Inventory tier: activation key stock.
- Customer credit tier: score such as GOOD/WATCH/HIGH_RISK/NEW.
- Service behavior tier: Standard/Premium runtime policy.

Use service behavior tier for all runtime decisions.
