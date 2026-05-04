# EMI Locker Database

PostgreSQL database schema and migrations for the EMI Locker Platform.

## Overview

This directory contains:
- **migrations/** - Database schema migrations (numbered sequentially)
- **seeds/** - Initial data for roles and reference data

## Migration Files

| File | Description |
|------|-------------|
| `001_users.sql` | Users table with roles (admin, dealer, reseller, user) |
| `002_devices.sql` | Devices table with IMEI, status, and ownership |
| `003_activation_keys.sql` | Device activation keys for enrollment |
| `004_emi_schedules.sql` | EMI payment schedules and terms |
| `005_emi_payments.sql` | Payment records and transaction history |
| `006_lock_requests.sql` | Device lock/unlock request queue |
| `007_decoupling.sql` | Device decoupled status after full payment |
| `008_audit_log.sql` | Comprehensive audit logging |
| `009_security_events.sql` | Security event tracking |
| `010_paut_tokens.sql` | PAUT (Push Authentication Token) management |
| `011_commands.sql` | Remote device command queue |

## Seeding

| File | Description |
|------|-------------|
| `roles.sql` | Initial role definitions |

## Running Migrations

```bash
# From backend directory
npm run migrate

# To rollback last migration
npm run migrate:rollback
```

## Database Connection

Configuration is managed via environment variables in the backend `.env` file:
- `DATABASE_URL` - Full connection string
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` - Individual components

## Schema Design

### Users Table
- Role-based access (admin, dealer, reseller, user)
- Phone number as primary identifier
- NID (National ID) for verification

### Devices Table
- IMEI as unique identifier
- Status: pending, active, locked, decoupled
- Links to owner and enrolling dealer

### EMI Schedules
- Configurable payment terms
- Links device to payment schedule
- Tracks total amount and monthly payment

### Payments
- Transaction records with payment method
- Links to EMI schedule
- Status: pending, completed, failed, overdue

### Security Events
- Failed login attempts
- Device policy violations
- Admin actions audit trail

## Security

- All PII (Personal data) encrypted at rest
- NID numbers hashed
- Audit logging on all sensitive operations
- Row-level security where applicable

## Backup

Regular backups recommended. Use pg_dump for full database backup: