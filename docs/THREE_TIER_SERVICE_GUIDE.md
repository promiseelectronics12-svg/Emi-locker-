# EMI Locker Three-Tier Service Guide

Status: Draft service contract for backend, dealer app, user app, and future VIP payment app implementation.

Purpose: keep every developer, AI model, tester, and business operator aligned on what `standard`, `premium`, and `vip` mean. A tier must never be treated as a cosmetic label only. It changes backend policy, dealer workflow, customer experience, lock behavior, payment handling, and support expectations.

## Naming Rule

| Internal value | Public label | Meaning |
| --- | --- | --- |
| `standard` | Normal | Manual dealer-controlled EMI protection |
| `premium` | Premium | Backend-assisted automation with dealer payment control |
| `vip` | VIP | Payment-ledger driven automation with a separate customer payment app/portal |

Use the internal values in code and database. Use the public labels in dealer/customer UI.

## Product Principle

EMI Locker must protect both parties:

- Dealer protection: collateral cannot disappear silently, payment default must be visible, and lock/unlock must be auditable.
- Customer dignity: the customer must understand due dates, payment status, grace period, support path, and why any restriction is applied.
- Enforcement ladder: reminder first, disturbance second, restriction third, full lock only when business rules justify it.

The product should not feel like punishment by default. It should feel like a structured EMI assistant that becomes strict only when rules are broken.

## Tier Summary

| Tier | Target client | Payment handling | Lock behavior | Dealer workload | Customer experience |
| --- | --- | --- | --- | --- | --- |
| Normal | Small shops, manual dealers | Dealer handles payments outside system | Dealer manually locks/unlocks after notification | High | Basic EMI protection and contact flow |
| Premium | Serious dealers wanting automation | Dealer records/confirms payment manually | Backend auto-reminds and auto-locks; dealer unlocks/confirms | Medium | EMI schedule, reminders, clear lock reason |
| VIP | Large dealers/chains/finance partners | Verified online/manual payment ledger; future payment gateway/webhook | Backend auto-reminds, applies VIP disturbance mode, and auto-relaxes/unlocks after verified payment | Low | Separate payment app/portal with balance, installments, advance payment, receipt |

## Normal Tier

### Business Promise

Normal is the low-cost, dealer-operated tier. The platform gives the dealer the tools, but the dealer makes decisions.

### Backend Behavior

- Store device as `service_tier = 'standard'`.
- Create and store EMI schedule during confirmed enrollment.
- Send due/overdue notifications to dealer.
- Do not auto-lock because payment collection is manual.
- Allow dealer-triggered lock/unlock if ownership and device policy are valid.
- Store all lock/unlock commands and device confirmations.
- Keep heartbeat, online/offline, permission health, FCM token state, and last known location.

### Dealer App Behavior

- Show key as `Normal`.
- Explain: "Manual payment tracking. Dealer receives overdue alerts and controls lock/unlock."
- Device detail must show:
  - EMI term summary
  - Due date
  - Last payment marker if entered
  - Lock state
  - Last heartbeat/online status
  - Manual lock/unlock buttons
- No infinite spinner. Every action must show `accepted`, `waiting for device`, `applied`, `failed`, or `expired`.

### User App Behavior

- Core user app acts as the managed device agent.
- Shows basic EMI schedule/status if available.
- Shows friendly reminder and dealer contact.
- Applies manual lock/unlock commands from backend.
- Reports heartbeat, lock state, permission health, location result, and offline unlock state.

### Payment App

Not required for Normal.

## Premium Tier

### Business Promise

Premium reduces dealer workload. The backend watches EMI dates and applies rules automatically, but the dealer still controls payment confirmation and final unlock decisions.

### Backend Behavior

- Store device/schedule as `service_tier = 'premium'`.
- Run scheduler rules:
  - Before due date: reminder notification.
  - Due date: payment due alert.
  - After grace period: reminder mode or partial lock.
  - Longer overdue: full lock if configured.
- Payment can be recorded by dealer/admin.
- Unlock should require dealer/admin action, except temporary grace unlock.
- Do not let unlock bypass payment/business rules.
- Emit SSE to dealer for due alerts, auto-lock, payment recorded, unlock, heartbeat changes, and permission degradation.

### Dealer App Behavior

- Show key as `Premium`.
- Explain: "Automatic reminders and overdue lock rules. Dealer confirms payment and unlocks."
- Device detail must show:
  - Next due date
  - Grace period
  - Automation status
  - Overdue days
  - Lock ladder stage
  - Payment recorded count
  - Manual payment record/confirm action
  - Unlock/grace action
- Dealer should see automation timeline:
  - Reminder sent
  - Warning shown
  - Partial lock applied
  - Full lock applied
  - Device confirmed state

### User App Behavior

- Core user app shows:
  - EMI schedule
  - Installments left
  - Due date
  - Grace period
  - Payment recorded message
  - Lock reason
  - Dealer contact
- Applies backend automation commands.
- Reports applied state back through heartbeat or command-result route.
- Offline unlock/grace flow must remain available for field rescue.

### Payment App

Not required for Premium. Optional later as an add-on, but not part of baseline Premium.

## VIP Tier

### Business Promise

VIP is the PalmPay-style tier: customer payment experience becomes part of the product. The dealer receives payment notifications and exceptions, while the system handles payment verification and lock-state relaxation automatically.

### Backend Behavior

- Store device/schedule as `service_tier = 'vip'`.
- Create payment ledger for every installment.
- Payment states must be explicit:
  - `due`
  - `pending`
  - `verified`
  - `rejected`
  - `refunded`
  - `settled_to_dealer`
- Support advance payment and early payoff.
- Support idempotent payment confirmation:
  - Gateway webhook later.
  - Admin/dealer verification fallback during early rollout.
- After verified payment:
  - Update installment/payment ledger.
  - Recalculate overdue state.
  - If current payment is cleared, send unlock/relax command automatically.
  - Notify dealer.
  - Notify customer.
- Dealer should not need to manually unlock after a verified VIP payment unless exception handling is required.
- Full lock should not be the first VIP response. Use VIP disturbance mode before stronger restriction.

### VIP Lock Ladder

| Stage | When | User impact |
| --- | --- | --- |
| Friendly reminder | Before due date | Notification and payment app prompt |
| Payment due | Due date/grace start | Persistent payment card in payment app and user app |
| VIP disturbance mode | After grace if unpaid | Front message/overlay that obstructs view but keeps payment/support path usable |
| Partial restriction | Continued overdue or tamper | Restrict distracting/non-essential apps if Device Owner policy allows |
| Full lock | Serious default/fraud/admin rule | Kiosk/lock mode with emergency, payment, and dealer contact only |

### Dealer App Behavior

- Show key as `VIP`.
- Explain: "Customer payment app, verified payment ledger, auto-relax/unlock after payment, dealer receives notifications."
- Device detail must show:
  - Customer payment app installed/synced status
  - Amount due
  - Installments left
  - Advance payment status
  - Last payment verification
  - Settlement status for dealer
  - Current lock ladder stage
  - Exceptions requiring dealer/admin action
- Dealer gets notifications:
  - Payment received
  - Payment verified
  - Device auto-unlocked/relaxed
  - Payment failed/rejected
  - Customer overdue
  - Device offline/degraded

### User App Behavior

- Core user app remains the enforcement/management agent.
- It should understand tier from backend and local schedule.
- It must not become three separate lock apps.
- For VIP, it should:
  - Link to/open the payment app.
  - Keep payment app allowed during disturbance/lock states.
  - Report payment app installed status if possible.
  - Apply VIP disturbance mode before harsher lock modes.
  - Report lock/relax state back to backend.

### VIP Payment App Behavior

This is a separate customer-facing app/portal, not the core enforcement agent.

Must show:

- Device/customer agreement summary.
- Total amount.
- Down payment.
- Monthly EMI.
- Installments paid/left.
- Next due date.
- Grace period.
- Pay now.
- Pay in advance.
- Payment pending/verified/rejected.
- Receipt/history.
- Dealer/support contact.
- "Why am I seeing this restriction?" explanation.

Must not control Device Owner policy directly. It talks to backend. Backend decides and tells the core user app/device policy what to do.

## App Separation Decision

Use one core user app plus one optional VIP payment app.

### Core User App

Installed on every managed EMI phone. It is responsible for:

- Device Owner / Device Admin behavior where available.
- FCM command receiver.
- Lock/overlay/kiosk behavior.
- Heartbeat.
- Permission/device health reporting.
- Offline unlock support.
- Schedule sync.
- Location report.
- Lock-state report.

### VIP Payment App

Installed only for VIP devices. It is responsible for:

- Customer payment UX.
- Payment initiation.
- Payment status display.
- Receipt/history.
- Advance payment.
- Support/customer communication.

### Why Not Three Separate User Apps?

Do not create separate Normal/Premium/VIP user apps. That creates maintenance pain, inconsistent security behavior, and testing explosion. The core user app should read `service_tier` and server policy, then behave accordingly.

## VIP Payment App Installation

For Device Owner / AMAPI-managed phones, the backend can apply a policy that includes the VIP payment app package with `installType: FORCE_INSTALLED`.

Example policy idea:

```json
{
  "applications": [
    {
      "packageName": "com.emilocker.user",
      "installType": "FORCE_INSTALLED"
    },
    {
      "packageName": "com.emilocker.payment",
      "installType": "FORCE_INSTALLED"
    }
  ]
}
```

Only add the payment app package for VIP devices. Normal/Premium devices should not receive it unless the dealer upgrades the key.

Reference: Android Management API supports installing Google Play apps by package name through device policy, including force-installed apps.

## Backend Data Model Required

Minimum fields to add or verify:

| Entity | Field | Purpose |
| --- | --- | --- |
| `devices` or `emi_schedules` | `service_tier` | Runtime policy tier: `standard`, `premium`, `vip` |
| `activation_keys` | `tier` | Stock/inventory key tier, already exists |
| `enrollments` | `tier` | Pending enrollment selected tier, already exists |
| `emi_schedules` | `service_tier` | Preferred place if tier is tied to agreement |
| `emi_payments` | normalized status fields | One canonical payment state |
| `payment_events` | event log | Idempotent webhook/manual confirmation history |
| `device_commands` | command lifecycle | `created`, `sent`, `received`, `applied`, `failed`, `expired` |

Rule: key tier must be copied into confirmed device/schedule tier during `confirmFromDevice()`.

## Backend Tier Policy Matrix

| Capability | Normal | Premium | VIP |
| --- | --- | --- | --- |
| EMI schedule stored | Yes | Yes | Yes |
| Dealer overdue notification | Yes | Yes | Yes |
| Customer due reminder | Basic | Yes | Yes |
| Auto-lock scheduler | No | Yes | Yes |
| Dealer manual lock | Yes | Yes | Exception/manual override |
| Dealer manual unlock | Yes | Yes | Exception/manual override |
| Payment ledger | Optional/manual | Dealer-recorded | Required |
| Payment app | No | No | Yes |
| Auto-unlock after verified payment | No | Optional later | Yes |
| Advance payment | No | Optional | Yes |
| Settlement tracking | No | Optional | Yes |
| VIP disturbance mode | No | Optional | Yes |

## Heartbeat And Backend Noise

Heartbeat is necessary, but it must be controlled. It should not become a database-noise machine.

### Recommended Heartbeat Policy

| Situation | Frequency |
| --- | --- |
| Healthy online device | Every 60 minutes |
| Device recently locked/unlocked | Immediately once, then return to normal |
| Permission degraded | Report at first reliable touchpoint and repeat every 15 minutes until fixed |
| Location pull | Only when requested, not continuous |
| FCM token changed | Immediately |
| App start/service restart | Immediately |

### Request Count Estimate

| Devices | 60-minute heartbeat | 15-minute heartbeat |
| ---: | ---: | ---: |
| 1,000 | 24,000/day, about 720,000/month | 96,000/day, about 2.88M/month |
| 10,000 | 240,000/day, about 7.2M/month | 960,000/day, about 28.8M/month |
| 100,000 | 2.4M/day, about 72M/month | 9.6M/day, about 288M/month |

### Traffic Estimate

If a heartbeat response is kept near 1 KB outbound:

| Devices | 60-minute heartbeat outbound/month | 15-minute heartbeat outbound/month |
| ---: | ---: | ---: |
| 1,000 | About 0.7 GB | About 2.9 GB |
| 10,000 | About 7.2 GB | About 28.8 GB |
| 100,000 | About 72 GB | About 288 GB |

If payloads grow to 5 KB, multiply those numbers by 5.

### Practical Conclusion

1,000 devices are manageable if heartbeat is hourly and payloads are small.

10,000 devices require paid backend hosting, DB indexes, and careful scheduler design.

100,000 devices require queueing, batching, paid infrastructure, observability, and probably multiple workers.

Render free tier is not acceptable for production. It can spin down after 15 minutes idle, has free monthly usage limits, does not support scaling beyond one instance, and Render explicitly says free instances should not be used for production applications.

## Backend Load Guardrails

- Use hourly heartbeat for healthy devices.
- Do not store a new row for every normal heartbeat; update device last-seen state.
- Store event rows only for meaningful state changes:
  - online to delayed/offline
  - healthy to degraded
  - lock state changed
  - FCM token invalid
  - payment state changed
  - location report received
- Keep heartbeat payload compact.
- Index:
  - `devices(last_seen_at)`
  - `devices(service_tier)`
  - `devices(device_health_status)`
  - `emi_schedules(device_id, status, service_tier)`
  - `emi_payments(emi_schedule_id, status/payment_status)`
  - `device_commands(device_id, status, created_at)`
- Scheduler must process in batches, not load the entire fleet at once.
- Use idempotency keys for payment events.
- Do not put Redis in the critical correctness path for lock/payment state.

## Immediate Implementation Plan

### Step 1: Backend Source Of Truth

- Add `service_tier` to active schedule or device runtime model.
- Copy enrollment/key tier into active schedule/device during confirmation.
- Expose tier in dealer device list, lock detail, user schedule refresh, and heartbeat response if needed.

### Step 2: Tier-Aware Scheduler

- Change auto-lock scheduler:
  - `standard`: notify dealer only.
  - `premium`: use current reminder/partial/full automation.
  - `vip`: use payment-ledger automation and VIP disturbance mode before full lock.

### Step 3: Payment Ledger Cleanup

- Pick one canonical payment table/route set.
- Normalize `status` vs `payment_status`.
- Add payment event idempotency.
- Add verified-payment-to-unlock pipeline for VIP.

### Step 4: Dealer App Tier Explanation

- In key purchase/selection UI, show a tier detail sheet.
- In binding wizard, show selected tier behavior.
- In device detail, show tier badge and tier-specific actions.

### Step 5: User App Tier Behavior

- Core user app reads tier from backend.
- Normal: basic schedule/lock support.
- Premium: automation explanation and richer schedule.
- VIP: payment app handoff, persistent payment status, VIP disturbance behavior.

### Step 6: VIP Payment App

- Create after backend ledger is stable.
- Start with payment status and manual proof/verification if gateway is not ready.
- Add gateway integration/webhooks later.

## Developer Rule

Any code that reads `tier` must answer this question:

"Is this tier an inventory tier, a customer credit tier, or a service behavior tier?"

Do not mix them.

- Inventory tier: activation key stock.
- Customer credit tier: customer score such as GOLD/SILVER/BRONZE.
- Service behavior tier: Normal/Premium/VIP runtime policy.

The new production behavior must use service behavior tier.
