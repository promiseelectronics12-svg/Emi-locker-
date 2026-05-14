# EMI Locker Database Schema Map

This is the living schema map for tables that affect runtime flows. Keep this aligned with Neon migrations and backend code.

## Critical Tables

| Table | Flow | Purpose | Important fields to track |
| --- | --- | --- | --- |
| `devices` | All device operations | Main enrolled device record | `id`, `dealer_id`, `fcm_token`, `last_seen_at`, `device_health_status`, `fcm_token_status`, `app_uninstall_suspected_at`, lock fields |
| `pending_enrollments` | Enrollment | Stores binding state before device confirmation | binding code, customer data, EMI terms, status |
| `emi_schedules` | EMI/reminders | Active finite EMI contract after device confirms | `total_amount`, `down_payment`, `emi_amount`, `duration`, `start_date`, `grace_days` |
| `location_pulls` | Pull location | Dealer request state | `device_id`, status, expiry, completed timestamp |
| `device_locations` | Pull/history | Reported GPS points | `device_id`, `latitude`, `longitude`, `accuracy`, `timestamp`, `pull_id` |
| `device_events` | Runtime/device reports | Device command results and permission/status reports | event type, payload, created timestamp |
| `evidence_records` | Evidence vault | Metadata for encrypted dealer-owned evidence | device/customer reference, encrypted file refs, status |
| `audit_logs` | Security | Admin/dealer action history | actor, action, target, created timestamp |

## Schema Update Rule

When a migration changes one of these tables:

1. Add the migration file or schema update.
2. Apply it to the correct Neon branch.
3. Record it in this file.
4. Add or update the QC test that proves the column/table is used correctly.

## Recent Runtime Columns

| Table | Column | Why it exists |
| --- | --- | --- |
| `devices` | `last_seen_at` | Dealer needs to know when device last communicated |
| `devices` | `device_health_status` | Shows online/offline/degraded state |
| `devices` | `fcm_token_status` | Identifies invalid push target or suspected app removal |
| `devices` | `app_uninstall_suspected_at` | Distinguishes app removed suspicion from normal offline |
| `devices` | `last_heartbeat_source` | Records what caused latest health update |

## Runtime Status Values

| Table | Field | Allowed runtime values |
| --- | --- | --- |
| `devices` | `status` | `pending`, `enrolled`, `active`, `locked`, `unlocked`, `partial_lock`, `reminder`, `pending_lock`, `pending_unlock`, `pending_decouple`, `decoupled`, `disabled`, `suspended`, `stolen` |

Migration `123_device_pending_statuses.sql` aligns the live Neon `devices_status_check` constraint with backend command states. This prevents dealer lock/unlock requests from failing while the backend waits for device confirmation.
