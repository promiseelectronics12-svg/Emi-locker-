# EMI Locker Platform — Unified Implementation Plan
**SUPERSEDED 2026-05-19.** This document predates the 3-app architecture decision and uses old "fake SIM Toolkit UI" / deceptive framing — now replaced by honest `DeviceProtectionService` + `EMI Locker` Customer Protection Layer model. Current architecture: `docs/CURRENT_ARCHITECTURE_AND_SUPERSEDED_PLANS.md`. Do NOT implement from this file.

---

## Context & Scale

This system will handle 10 lakh+ (1,000,000+) activation keys every six months (~5,500/day peak). The backend must be the single source of truth. Frontend clients (Admin Panel, Dealer App, User App) are consumers of the backend — they never hold business logic.

---

## Pre-Made Decisions (Codex must not reconsider these)

| Topic | Decision |
|---|---|
| Key table name | `activation_keys` (matches proper migration) |
| Key statuses | `available` → `assigned` → `activated` → `revoked` |
| Key request statuses | `pending` → `approved` / `rejected` |
| Key ID type | UUID everywhere |
| Key storage | `key_string` plaintext + HMAC-SHA256 signature stored alongside it |
| Key expiry | No expiry. `expires_at` column removed from activation_keys |
| Reseller quota column | `monthly_quota` (NOT `monthly_key_quota`) |
| Approval code path | Only `/api/v1/admin/key-requests/:id/approve` (admin path). Delete the duplicate `/api/v1/keys/approve` route |
| Admin panel page pattern | Folder-based pages only (`pages/resellers/index.tsx`, `pages/key-requests/index.tsx`, etc.) |
| Sidebar nav data source | `nav.ts` only — never hardcode in `Sidebar.tsx` |
| Dealer identity | `dealers.user_id` links to `users.id`. Throughout the code, "dealer_id" always means the dealer's `users.id` value (which equals `dealers.user_id`) |
| Device schema | `serial` and `customer_id` are nullable (not available at enrollment time) |
| TOTP time window | 1800 seconds (30 minutes) per step, ±1 window = up to 90 min validity |
| Payment table | Extend existing `emi_payments` with Bkash fields. No new separate payment table |
| Bkash integration | Dealer sets their Bkash merchant number. Platform acts as aggregator |

---

## Phase 0 — Database Unification (Run First, Before Any Code Changes)

Create file: `backend/scripts/099_unify_schema.sql`

This is a **fully idempotent** migration. Every statement is safe to re-run N times.

> **DESIGN PRINCIPLES**:
> - **No blind drops**: Legacy tables are renamed (`_legacy_*`), never destroyed. Canonical tables are patched in-place, never recreated.
> - **Never invent ownership**: Rows with NULL/invalid `reseller_id` are archived to `_legacy_activation_keys_orphans`, never backfilled with a random user. Only safe, non-ownership defaults (empty strings, 0, `NOW()`) are used.
> - **Column fingerprinting**: `activation_keys` detected as legacy if it has `key_hash`/`key_code` but lacks `key_string`. Canonical tables get **full parity enforcement** via strict 7-step order: add columns → archive invalid rows → clean nullable FK refs → backfill safe defaults → enforce NOT NULL → drop old constraints → add new constraints/FKs.
> - **Clean before constrain**: Invalid nullable FK references (`dealer_id`, `device_id`, `request_id` pointing to missing records) are set to NULL before FK constraints are added. Invalid NOT NULL candidates (`key_string IS NULL`, `reseller_id` not in `users`) are archived and deleted before `SET NOT NULL`.
> - **Orphan archiving**: Reseller rows with no matching `users.id` → `_legacy_resellers`. Key requests with dangling `reseller_id` → `_legacy_key_requests`. Activation keys with bad ownership → `_legacy_activation_keys_orphans`. No data is deleted without an archive copy.
> - **FK rebuilds**: `key_requests.reseller_id` data is remapped from `resellers.id` → `users.id` before the FK is dropped and rebuilt.
> - **Generic constraint drops**: All CHECK constraint drops use `pg_constraint` + `pg_attribute` lookups (not hardcoded names) to handle any naming convention from any prior migration.
> - **Value mapping**: `devices.lock_level` old values are mapped (`soft→SOFT`, `hard→FULL`, `wipe→WIPE`, unknown→`NONE`) before the canonical constraint is added.
> - **Type normalization**: `devices.fcm_token` TEXT is renamed to `_old`, replaced with BYTEA. ENUM columns in `emi_payments` are cast to TEXT before renaming.
> - **Dependency-safe drops**: ENUM types (`payment_status`, `payment_method`, `activation_key_status`) are only dropped after confirming no column still depends on them.
> - **Dynamic archive names**: Archive table fallbacks use `to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US')` suffixes with quoted identifiers, never fixed names like `_2`. Re-runs always succeed even inside the same second.
> - **`_legacy_*` tables**: Use `INCLUDING DEFAULTS INCLUDING STORAGE` only (no UNIQUE/FK/CHECK) to avoid constraint conflicts with canonical tables.
> - **Replay prevention**: `used_challenges` table with UNIQUE PRIMARY KEY on challenge UUID.

```sql
-- ============================================================
-- 099_unify_schema.sql
-- EMI Locker Platform — Canonical Schema Unification
--
-- DESIGN: Every statement is idempotent. Safe to re-run N times.
-- No DROP TABLE on canonical tables. Uses ALTER + IF NOT EXISTS.
-- Legacy tables are renamed, never destroyed.
-- ============================================================

BEGIN;

-- ══════════════════════════════════════════════════════════════
-- PHASE A: Patch/rename legacy objects (idempotent)
-- ══════════════════════════════════════════════════════════════

-- ── 0a. RESELLERS — patch existing rows + schema ─────────────
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'resellers') THEN

    -- Add columns that may be missing:
    ALTER TABLE resellers ADD COLUMN IF NOT EXISTS user_id UUID;
    ALTER TABLE resellers ADD COLUMN IF NOT EXISTS business_name TEXT NOT NULL DEFAULT '';
    ALTER TABLE resellers ADD COLUMN IF NOT EXISTS used_keys INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE resellers ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';
    ALTER TABLE resellers ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
    ALTER TABLE resellers ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

    -- Copy monthly_key_quota → monthly_quota before dropping:
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'resellers' AND column_name = 'monthly_key_quota') THEN
      ALTER TABLE resellers ADD COLUMN IF NOT EXISTS monthly_quota INTEGER NOT NULL DEFAULT 100;
      UPDATE resellers SET monthly_quota = monthly_key_quota WHERE monthly_key_quota IS NOT NULL;
      ALTER TABLE resellers DROP COLUMN monthly_key_quota;
    ELSE
      ALTER TABLE resellers ADD COLUMN IF NOT EXISTS monthly_quota INTEGER NOT NULL DEFAULT 100;
    END IF;

    -- Backfill user_id for existing rows that have NULL:
    -- Only set user_id = id where that id actually exists in the users table.
    UPDATE resellers SET user_id = id
      WHERE user_id IS NULL
      AND EXISTS (SELECT 1 FROM users WHERE users.id = resellers.id);

    -- Move orphan rows (user_id still NULL) to legacy table instead of deleting:
    -- This preserves data lineage for audit purposes.
    -- Use INCLUDING DEFAULTS only — avoids copying UNIQUE/FK/CHECK constraints
    -- that would conflict with the canonical resellers table.
    IF EXISTS (SELECT 1 FROM resellers WHERE user_id IS NULL) THEN
      CREATE TABLE IF NOT EXISTS _legacy_resellers (
        LIKE resellers INCLUDING DEFAULTS INCLUDING STORAGE
      );
      INSERT INTO _legacy_resellers SELECT * FROM resellers WHERE user_id IS NULL
        ON CONFLICT DO NOTHING;
      DELETE FROM resellers WHERE user_id IS NULL;
    END IF;

    -- Now safe to enforce NOT NULL:
    ALTER TABLE resellers ALTER COLUMN user_id SET NOT NULL;

    -- Add UNIQUE constraint if missing:
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                   WHERE table_name = 'resellers' AND constraint_type = 'UNIQUE'
                   AND constraint_name LIKE '%user_id%') THEN
      ALTER TABLE resellers ADD CONSTRAINT resellers_user_id_unique UNIQUE (user_id);
    END IF;
  END IF;
END $$;

-- ── 0b. KEY_REQUESTS — patch FK, columns, and data ───────────
DO $$
DECLARE
  fk_name TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'key_requests') THEN

    ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS approved_quantity INTEGER;
    ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS approved_by UUID;
    ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
    ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS rejected_by UUID;
    ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;
    ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
    UPDATE key_requests SET status = LOWER(status) WHERE status != LOWER(status);

    -- Drop old status CHECK constraint (may use wrong values):
    ALTER TABLE key_requests DROP CONSTRAINT IF EXISTS key_requests_status_check;

    -- MIGRATE DATA: If reseller_id currently points to old resellers.id (not users.id),
    -- remap it to the reseller's users.id via the resellers.user_id lookup:
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_name = 'resellers') THEN
      UPDATE key_requests kr
        SET reseller_id = r.user_id
        FROM resellers r
        WHERE kr.reseller_id = r.id
        AND kr.reseller_id != r.user_id
        AND r.user_id IS NOT NULL;
    END IF;

    -- Archive orphan key_requests whose reseller_id does not exist in users:
    -- This prevents the new FK from failing on dangling references.
    IF EXISTS (SELECT 1 FROM key_requests kr
               WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = kr.reseller_id)) THEN
      CREATE TABLE IF NOT EXISTS _legacy_key_requests (
        LIKE key_requests INCLUDING DEFAULTS INCLUDING STORAGE
      );
      INSERT INTO _legacy_key_requests
        SELECT * FROM key_requests kr
        WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = kr.reseller_id)
        ON CONFLICT DO NOTHING;
      DELETE FROM key_requests kr
        WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = kr.reseller_id);
    END IF;

    -- Drop ALL existing FKs on reseller_id:
    FOR fk_name IN
      SELECT tc.constraint_name FROM information_schema.table_constraints tc
      WHERE tc.table_name = 'key_requests' AND tc.constraint_type = 'FOREIGN KEY'
      AND tc.constraint_name LIKE '%reseller_id%'
    LOOP
      EXECUTE format('ALTER TABLE key_requests DROP CONSTRAINT %I', fk_name);
    END LOOP;

    -- Rebuild FK to point to users(id):
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                   WHERE table_name = 'key_requests' AND constraint_type = 'FOREIGN KEY'
                   AND constraint_name = 'key_requests_reseller_id_fkey') THEN
      ALTER TABLE key_requests ADD CONSTRAINT key_requests_reseller_id_fkey
        FOREIGN KEY (reseller_id) REFERENCES users(id) ON DELETE RESTRICT;
    END IF;
  END IF;
END $$;

-- ── 0c. ACTIVATION_KEYS — rename legacy, never drop canonical ─
DO $$ BEGIN
  ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_activation_key_id_fkey;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'activation_keys') THEN

    -- Check if this is an OLD table (has key_hash or key_code, lacks key_string):
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'activation_keys'
               AND column_name IN ('key_hash', 'key_code'))
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_name = 'activation_keys' AND column_name = 'key_string') THEN

      -- Detach the legacy table from the enum BEFORE we drop the type:
      -- ALTER the status column to TEXT so the enum can be dropped safely.
      IF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'activation_keys' AND column_name = 'status'
                 AND udt_name = 'activation_key_status') THEN
        ALTER TABLE activation_keys ALTER COLUMN status TYPE TEXT;
      END IF;

      -- Rename to preserve for inspection (dynamic suffix — never fixed names):
      DECLARE archive_name TEXT;
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                       WHERE table_name = '_legacy_activation_keys') THEN
          ALTER TABLE activation_keys RENAME TO _legacy_activation_keys;
        ELSE
          archive_name := '_legacy_activation_keys_' || to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US');
          EXECUTE format('ALTER TABLE activation_keys RENAME TO %I', archive_name);
        END IF;
      END;

    ELSE
      -- ════════════════════════════════════════════════════════
      -- It HAS key_string — this is the canonical table.
      -- Ensure FULL PARITY with Phase B's CREATE TABLE definition.
      --
      -- STRICT ORDER:
      --   1. Add missing nullable columns
      --   2. Archive invalid rows that cannot be safely repaired
      --   3. Null out invalid nullable FK references
      --   4. Backfill only safe defaults (never invent ownership)
      --   5. Enforce NOT NULL
      --   6. Drop old conflicting constraints
      --   7. Add new constraints / FKs
      -- ════════════════════════════════════════════════════════

      -- ─── STEP 0.5: Cast status from enum to TEXT if needed ─────
      -- If canonical-ish table still uses activation_key_status enum:
      IF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'activation_keys' AND column_name = 'status'
                 AND udt_name = 'activation_key_status') THEN
        ALTER TABLE activation_keys ALTER COLUMN status TYPE TEXT;
      END IF;
      -- Map old status values to canonical BEFORE archiving/constraining:
      UPDATE activation_keys SET status = 'revoked' WHERE status IN ('expired', 'suspended');
      UPDATE activation_keys SET status = 'available' WHERE status IN ('pending', 'generated', 'approved');
      UPDATE activation_keys SET status = 'activated' WHERE status = 'consumed';

      -- ─── STEP 1: Add missing columns (all nullable initially) ──
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS reseller_id UUID;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS dealer_id UUID;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS device_id UUID;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS request_id UUID;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS hmac_signature TEXT;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS nonce VARCHAR(64);
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS sig_timestamp BIGINT;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS status TEXT;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS imei_hash TEXT;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS imei BYTEA;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
      ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

      -- ─── STEP 2: Archive invalid rows (cannot be repaired) ─────
      -- Rows with NULL/empty key_string or reseller_id pointing nowhere
      -- are prototype/test data. Archive them, never invent ownership.
      CREATE TABLE IF NOT EXISTS _legacy_activation_keys_orphans (
        LIKE activation_keys INCLUDING DEFAULTS INCLUDING STORAGE
      );
      INSERT INTO _legacy_activation_keys_orphans
        SELECT * FROM activation_keys
        WHERE key_string IS NULL
           OR key_string = ''
           OR reseller_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = activation_keys.reseller_id)
        ON CONFLICT DO NOTHING;
      DELETE FROM activation_keys
        WHERE key_string IS NULL
           OR key_string = ''
           OR reseller_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = activation_keys.reseller_id);

      -- ─── STEP 3: Clean invalid nullable FK references ──────────
      -- These columns are nullable in the canonical schema, so NULL is safe.
      UPDATE activation_keys SET dealer_id = NULL
        WHERE dealer_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = activation_keys.dealer_id);
      UPDATE activation_keys SET device_id = NULL
        WHERE device_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM devices d WHERE d.id = activation_keys.device_id);
      UPDATE activation_keys SET request_id = NULL
        WHERE request_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM key_requests kr WHERE kr.id = activation_keys.request_id);

      -- ─── STEP 4: Backfill safe defaults (never invent ownership) ─
      UPDATE activation_keys SET hmac_signature = '' WHERE hmac_signature IS NULL;
      UPDATE activation_keys SET nonce = '' WHERE nonce IS NULL;
      UPDATE activation_keys SET sig_timestamp = 0 WHERE sig_timestamp IS NULL;
      UPDATE activation_keys SET status = 'available' WHERE status IS NULL;
      UPDATE activation_keys SET created_at = NOW() WHERE created_at IS NULL;
      UPDATE activation_keys SET updated_at = NOW() WHERE updated_at IS NULL;

      -- ─── STEP 5: Enforce NOT NULL ──────────────────────────────
      ALTER TABLE activation_keys ALTER COLUMN key_string SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN reseller_id SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN hmac_signature SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN nonce SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN sig_timestamp SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN status SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN status SET DEFAULT 'available';
      ALTER TABLE activation_keys ALTER COLUMN created_at SET NOT NULL;
      ALTER TABLE activation_keys ALTER COLUMN updated_at SET NOT NULL;

      -- ─── STEP 6: Drop old conflicting constraints ──────────────
      -- Drop ALL check constraints on status and ALL old FKs (any name):
      DECLARE
        chk_name TEXT;
        fk_name TEXT;
      BEGIN
        FOR chk_name IN
          SELECT con.conname FROM pg_constraint con
          JOIN pg_attribute att ON att.attnum = ANY(con.conkey)
            AND att.attrelid = con.conrelid
          WHERE con.conrelid = 'activation_keys'::regclass
            AND con.contype = 'c' AND att.attname = 'status'
        LOOP
          EXECUTE format('ALTER TABLE activation_keys DROP CONSTRAINT %I', chk_name);
        END LOOP;

        -- Drop ALL existing FKs on reseller_id, dealer_id, device_id, request_id
        -- (old migrations may have created FKs with non-canonical names,
        --  e.g. pointing to resellers(id) instead of users(id)):
        FOR fk_name IN
          SELECT con.conname FROM pg_constraint con
          JOIN pg_attribute att ON att.attnum = ANY(con.conkey)
            AND att.attrelid = con.conrelid
          WHERE con.conrelid = 'activation_keys'::regclass
            AND con.contype = 'f'
            AND att.attname IN ('reseller_id', 'dealer_id', 'device_id', 'request_id')
        LOOP
          EXECUTE format('ALTER TABLE activation_keys DROP CONSTRAINT %I', fk_name);
        END LOOP;
      END;

      -- ─── STEP 7: Add new constraints / FKs ─────────────────────
      ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_status_check
        CHECK (status IN ('available', 'assigned', 'activated', 'revoked'));

      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                     WHERE table_name = 'activation_keys' AND constraint_name = 'activation_keys_reseller_id_fkey') THEN
        ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_reseller_id_fkey
          FOREIGN KEY (reseller_id) REFERENCES users(id) ON DELETE RESTRICT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                     WHERE table_name = 'activation_keys' AND constraint_name = 'activation_keys_dealer_id_fkey') THEN
        ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_dealer_id_fkey
          FOREIGN KEY (dealer_id) REFERENCES users(id) ON DELETE SET NULL;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                     WHERE table_name = 'activation_keys' AND constraint_name = 'activation_keys_device_id_fkey') THEN
        ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_device_id_fkey
          FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                     WHERE table_name = 'activation_keys' AND constraint_name = 'activation_keys_request_id_fkey') THEN
        ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_request_id_fkey
          FOREIGN KEY (request_id) REFERENCES key_requests(id) ON DELETE SET NULL;
      END IF;
    END IF;
  END IF;
END $$;

-- Also detach _legacy table from enum if it still depends:
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = '_legacy_activation_keys')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = '_legacy_activation_keys' AND column_name = 'status'
                 AND udt_name = 'activation_key_status') THEN
    ALTER TABLE _legacy_activation_keys ALTER COLUMN status TYPE TEXT;
  END IF;
END $$;

-- Drop activation_key_status enum ONLY if no column still depends on it:
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE udt_name = 'activation_key_status' AND table_schema = 'public') THEN
    DROP TYPE IF EXISTS activation_key_status;
  END IF;
END $$;

-- Archive old `keys` table (if it exists) instead of dropping:
DO $$
DECLARE
  archive_name TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'keys') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_name = '_legacy_keys') THEN
      ALTER TABLE keys RENAME TO _legacy_keys;
    ELSE
      -- Dynamic suffix — never a fixed fallback name:
      archive_name := '_legacy_keys_' || to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US');
      EXECUTE format('ALTER TABLE keys RENAME TO %I', archive_name);
    END IF;
  END IF;
END $$;

-- ── 0d. DEVICES — full normalization ─────────────────────────

-- 0d-1. Normalize state → status (canonical lifecycle column):
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'devices' AND column_name = 'state')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_name = 'devices' AND column_name = 'status') THEN
    ALTER TABLE devices ALTER COLUMN state TYPE TEXT;
    ALTER TABLE devices RENAME COLUMN state TO status;
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name = 'devices' AND column_name = 'state')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'devices' AND column_name = 'status') THEN
    ALTER TABLE devices DROP COLUMN state;
  END IF;

  -- Drop device_state enum if no column still depends on it:
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE udt_name = 'device_state' AND table_schema = 'public') THEN
    DROP TYPE IF EXISTS device_state;
  END IF;
END $$;

-- 0d-2. Add ALL compatibility columns used by active backend code:
-- (deviceService.js, adminDeviceService.js, emiModel.js all use these)
ALTER TABLE devices ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'enrolled';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS serial_number TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS soc_id TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_name TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS brand TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS amapi_device_name TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS amapi_device_id TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS managed_google_account TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS enrollment_token TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS enrolled_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS policy_last_applied TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_hash TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_salt TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fcm_token_updated_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_reason TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_by UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS decoupling_initiated_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS decoupling_window_expires_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fraud_flagged BOOLEAN DEFAULT FALSE;

-- 0d-3. Normalize lock_level (handles INTEGER, TEXT, VARCHAR):
DO $$
DECLARE
  chk_name TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'devices' AND column_name = 'lock_level') THEN
    -- Safe conversion: create _new column, map ALL known input types:
    ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_level_new TEXT DEFAULT 'NONE';
    UPDATE devices SET lock_level_new = CASE
      WHEN lock_level IS NULL THEN 'NONE'
      WHEN lock_level::text IN ('0', 'NONE', 'none') THEN 'NONE'
      WHEN lock_level::text IN ('1', 'SOFT', 'soft') THEN 'SOFT'
      WHEN lock_level::text IN ('2', 'FULL', 'full', 'hard') THEN 'FULL'
      WHEN lock_level::text IN ('3', 'WIPE', 'wipe') THEN 'WIPE'
      ELSE 'NONE'
    END;

    -- Drop ALL check constraints on lock_level (any name):
    FOR chk_name IN
      SELECT con.conname FROM pg_constraint con
      JOIN pg_attribute att ON att.attnum = ANY(con.conkey)
        AND att.attrelid = con.conrelid
      WHERE con.conrelid = 'devices'::regclass
        AND con.contype = 'c' AND att.attname = 'lock_level'
    LOOP
      EXECUTE format('ALTER TABLE devices DROP CONSTRAINT %I', chk_name);
    END LOOP;

    ALTER TABLE devices DROP COLUMN lock_level;
    ALTER TABLE devices RENAME COLUMN lock_level_new TO lock_level;
    ALTER TABLE devices ALTER COLUMN lock_level SET NOT NULL;
    ALTER TABLE devices ALTER COLUMN lock_level SET DEFAULT 'NONE';
    ALTER TABLE devices ADD CONSTRAINT devices_lock_level_check
      CHECK (lock_level IN ('NONE', 'SOFT', 'FULL', 'WIPE'));
  ELSE
    -- lock_level does not exist at all: create it fresh
    ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_level TEXT NOT NULL DEFAULT 'NONE';
    ALTER TABLE devices ADD CONSTRAINT devices_lock_level_check
      CHECK (lock_level IN ('NONE', 'SOFT', 'FULL', 'WIPE'));
  END IF;
END $$;

-- 0d-4. Normalize fcm_token: if TEXT, rename to _old, add BYTEA version:
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'devices' AND column_name = 'fcm_token'
             AND data_type = 'text') THEN
    ALTER TABLE devices RENAME COLUMN fcm_token TO _fcm_token_text_old;
    ALTER TABLE devices ADD COLUMN fcm_token BYTEA;
  END IF;
END $$;

-- ══════════════════════════════════════════════════════════════
-- PHASE B: Create canonical tables (all IF NOT EXISTS, re-runnable)
-- ══════════════════════════════════════════════════════════════

-- ── 1. RESELLERS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS resellers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  business_name TEXT NOT NULL DEFAULT '',
  monthly_quota INTEGER NOT NULL DEFAULT 100 CHECK (monthly_quota > 0),
  used_keys     INTEGER NOT NULL DEFAULT 0 CHECK (used_keys >= 0),
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'active', 'suspended')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_resellers_user_id ON resellers(user_id);
CREATE INDEX IF NOT EXISTS idx_resellers_status ON resellers(status);

CREATE OR REPLACE FUNCTION update_resellers_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_resellers_updated_at ON resellers;
CREATE TRIGGER trg_resellers_updated_at
  BEFORE UPDATE ON resellers FOR EACH ROW EXECUTE FUNCTION update_resellers_updated_at();

-- ── 2. KEY_REQUESTS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS key_requests (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reseller_id      UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  quantity         INTEGER NOT NULL CHECK (quantity > 0),
  justification    TEXT NOT NULL DEFAULT '',
  status           TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_quantity INTEGER,
  approved_by      UUID REFERENCES users(id),
  approved_at      TIMESTAMPTZ,
  rejected_by      UUID REFERENCES users(id),
  rejected_at      TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_key_requests_reseller_id ON key_requests(reseller_id);
CREATE INDEX IF NOT EXISTS idx_key_requests_status ON key_requests(status);
CREATE INDEX IF NOT EXISTS idx_key_requests_created_at ON key_requests(created_at DESC);

CREATE OR REPLACE FUNCTION update_key_requests_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_key_requests_updated_at ON key_requests;
CREATE TRIGGER trg_key_requests_updated_at
  BEFORE UPDATE ON key_requests FOR EACH ROW EXECUTE FUNCTION update_key_requests_updated_at();

-- ── 3. ACTIVATION_KEYS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS activation_keys (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_string     VARCHAR(19) NOT NULL,
  reseller_id    UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  dealer_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  device_id      UUID REFERENCES devices(id) ON DELETE SET NULL,
  request_id     UUID REFERENCES key_requests(id) ON DELETE SET NULL,
  hmac_signature TEXT NOT NULL,
  nonce          VARCHAR(64) NOT NULL,
  sig_timestamp  BIGINT NOT NULL,
  status         TEXT NOT NULL DEFAULT 'available'
                 CHECK (status IN ('available', 'assigned', 'activated', 'revoked')),
  assigned_at    TIMESTAMPTZ,
  activated_at   TIMESTAMPTZ,
  imei           BYTEA,
  imei_hash      TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_activation_keys_key_string ON activation_keys(key_string);
CREATE INDEX IF NOT EXISTS idx_activation_keys_reseller_id ON activation_keys(reseller_id);
CREATE INDEX IF NOT EXISTS idx_activation_keys_dealer_id ON activation_keys(dealer_id);
CREATE INDEX IF NOT EXISTS idx_activation_keys_status ON activation_keys(status);
CREATE INDEX IF NOT EXISTS idx_activation_keys_imei_hash ON activation_keys(imei_hash);
CREATE INDEX IF NOT EXISTS idx_activation_keys_created_at ON activation_keys(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activation_keys_reseller_status ON activation_keys(reseller_id, status);
CREATE INDEX IF NOT EXISTS idx_activation_keys_dealer_status ON activation_keys(dealer_id, status);

CREATE OR REPLACE FUNCTION update_activation_keys_updated_at()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_activation_keys_updated_at ON activation_keys;
CREATE TRIGGER trg_activation_keys_updated_at
  BEFORE UPDATE ON activation_keys FOR EACH ROW EXECUTE FUNCTION update_activation_keys_updated_at();

-- ── 4. DEVICES — add missing columns ─────────────────────────
ALTER TABLE devices ALTER COLUMN serial DROP NOT NULL;
ALTER TABLE devices ALTER COLUMN customer_id DROP NOT NULL;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS imei_hash TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS reseller_id UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_level TEXT NOT NULL DEFAULT 'NONE';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_reason TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_by UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS activation_key_id UUID REFERENCES activation_keys(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS totp_secret TEXT;
-- fcm_token: type was normalized in Phase A (0d). Skip ADD if already exists.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fcm_token BYTEA;

-- Ensure lock_level constraint exists after Phase B ADD COLUMN:
-- Phase A handles pre-existing columns; this handles freshly-created ones.
DO $$
DECLARE
  chk_name TEXT;
BEGIN
  -- Drop any existing check constraints on lock_level (any name):
  FOR chk_name IN
    SELECT con.conname FROM pg_constraint con
    JOIN pg_attribute att ON att.attnum = ANY(con.conkey)
      AND att.attrelid = con.conrelid
    WHERE con.conrelid = 'devices'::regclass
      AND con.contype = 'c' AND att.attname = 'lock_level'
  LOOP
    EXECUTE format('ALTER TABLE devices DROP CONSTRAINT %I', chk_name);
  END LOOP;
  ALTER TABLE devices ADD CONSTRAINT devices_lock_level_check
    CHECK (lock_level IN ('NONE', 'SOFT', 'FULL', 'WIPE'));
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_imei_hash ON devices(imei_hash);
CREATE INDEX IF NOT EXISTS idx_devices_reseller_id ON devices(reseller_id);
CREATE INDEX IF NOT EXISTS idx_devices_lock_level ON devices(lock_level);

-- Restore devices.activation_key_id FK if it was dropped in Phase A (0c)
-- and the column already existed (so ADD COLUMN IF NOT EXISTS was a no-op):
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'devices' AND column_name = 'activation_key_id') THEN
    -- Clean invalid references before adding FK:
    UPDATE devices SET activation_key_id = NULL
      WHERE activation_key_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM activation_keys ak WHERE ak.id = devices.activation_key_id
      );
    -- Restore FK if missing:
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                   WHERE table_name = 'devices' AND constraint_type = 'FOREIGN KEY'
                   AND constraint_name = 'devices_activation_key_id_fkey') THEN
      ALTER TABLE devices ADD CONSTRAINT devices_activation_key_id_fkey
        FOREIGN KEY (activation_key_id) REFERENCES activation_keys(id) ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

-- ── 5. DEALERS — add Bkash + reseller link ───────────────────
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS reseller_id UUID REFERENCES users(id);
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS bkash_merchant_number VARCHAR(20);
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS bkash_enabled BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_dealers_reseller_id ON dealers(reseller_id);

-- ── 6. EMI_PAYMENTS — normalize + add Bkash fields ──────────
-- Existing migrations disagree on column names:
--   005: emi_schedule_id, payment_status, payment_method (TEXT)
--   006: emi_id, status (ENUM), method (ENUM), tx_id
--   prototype: schedule_id, status, method, tx_id, recorded_at
-- We normalize to canonical names. ADD COLUMN IF NOT EXISTS skips
-- if the column already exists under that name.
DO $$ BEGIN
  -- Ensure canonical FK column exists (may be named emi_schedule_id, schedule_id, or emi_id):
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'emi_schedule_id')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'schedule_id') THEN
    ALTER TABLE emi_payments RENAME COLUMN schedule_id TO emi_schedule_id;
  ELSIF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'emi_schedule_id')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'emi_id') THEN
    ALTER TABLE emi_payments RENAME COLUMN emi_id TO emi_schedule_id;
  END IF;

  -- Ensure canonical status column (may be payment_status or status):
  -- Also cast ENUM → TEXT if 006_emi_payments.sql used CREATE TYPE payment_status:
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'emi_payments' AND column_name = 'status'
             AND udt_name = 'payment_status') THEN
    ALTER TABLE emi_payments ALTER COLUMN status TYPE TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'payment_status')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'status') THEN
    ALTER TABLE emi_payments RENAME COLUMN status TO payment_status;
  END IF;

  -- Ensure canonical method column (may be method or payment_method):
  -- Cast ENUM → TEXT if 006_emi_payments.sql used CREATE TYPE payment_method:
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'emi_payments' AND column_name = 'method'
             AND udt_name = 'payment_method') THEN
    ALTER TABLE emi_payments ALTER COLUMN method TYPE TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'payment_method')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'method') THEN
    ALTER TABLE emi_payments RENAME COLUMN method TO payment_method;
  END IF;

  -- Ensure canonical tx column (may be tx_id or transaction_ref):
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'transaction_ref')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'emi_payments' AND column_name = 'tx_id') THEN
    ALTER TABLE emi_payments RENAME COLUMN tx_id TO transaction_ref;
  END IF;

  -- Cast payment_status to TEXT if it is still an ENUM after rename:
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'emi_payments' AND column_name = 'payment_status'
             AND data_type = 'USER-DEFINED') THEN
    ALTER TABLE emi_payments ALTER COLUMN payment_status TYPE TEXT;
  END IF;

  -- Cast payment_method to TEXT if it is still an ENUM after rename:
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'emi_payments' AND column_name = 'payment_method'
             AND data_type = 'USER-DEFINED') THEN
    ALTER TABLE emi_payments ALTER COLUMN payment_method TYPE TEXT;
  END IF;
END $$;

-- Drop orphaned ENUM types only if no column still depends on them:
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE udt_name = 'payment_status' AND table_schema = 'public') THEN
    DROP TYPE IF EXISTS payment_status;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE udt_name = 'payment_method' AND table_schema = 'public') THEN
    DROP TYPE IF EXISTS payment_method;
  END IF;
END $$;

-- Now add Bkash-specific columns:
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS dealer_id UUID REFERENCES users(id);
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS bkash_transaction_id TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS bkash_payment_id TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS merchant_ref TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS auto_unlocked BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS recorded_by UUID REFERENCES users(id);

CREATE INDEX IF NOT EXISTS idx_emi_payments_dealer_id ON emi_payments(dealer_id);
CREATE INDEX IF NOT EXISTS idx_emi_payments_bkash_tx_id ON emi_payments(bkash_transaction_id);
CREATE INDEX IF NOT EXISTS idx_emi_payments_merchant_ref ON emi_payments(merchant_ref);

-- ── 7. UNLOCK_CODES ──────────────────────────────────────────
-- One row per unlock code generation event.
-- Codes are TOTP — verified on-device, not here.
-- This table is the audit trail only.
CREATE TABLE IF NOT EXISTS unlock_codes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id    UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  generated_by UUID NOT NULL REFERENCES users(id),  -- dealer who generated
  purpose      TEXT NOT NULL DEFAULT 'manual_unlock'
               CHECK (purpose IN ('manual_unlock', 'cash_payment_confirm')),
  valid_until  TIMESTAMPTZ NOT NULL,
  used         BOOLEAN NOT NULL DEFAULT FALSE,
  used_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_unlock_codes_device_id ON unlock_codes(device_id);
CREATE INDEX IF NOT EXISTS idx_unlock_codes_generated_by ON unlock_codes(generated_by);
CREATE INDEX IF NOT EXISTS idx_unlock_codes_valid_until ON unlock_codes(valid_until);

-- ── 8. AUDIT LOG — ensure canonical columns exist ────────────
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS target_type VARCHAR(50);
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS target_id VARCHAR(255);
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS ip_address INET;

-- ── 9. USED_CHALLENGES — QR replay prevention ───────────────
-- Each QR challenge UUID can only be consumed once.
-- consumeKey INSERTs here; duplicate = replay attack → reject.
CREATE TABLE IF NOT EXISTS used_challenges (
  challenge VARCHAR(64) PRIMARY KEY,
  used_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Periodically purge entries older than 1 hour via scheduler.

COMMIT;
```

**Canonical column name reference** (for any code that touches `emi_payments`):

| If migration created... | Canonical name used by all backend code |
|---|---|
| `emi_id` | `emi_schedule_id` |
| `status` (ENUM) | `payment_status` (TEXT) |
| `method` (ENUM) | `payment_method` (TEXT) |
| `tx_id` | `transaction_ref` |

---

## Phase 1 — Backend: Single Canonical Code Path

### 1A. DELETE these files entirely

- `backend/src/modules/keys/schema.sql` — superseded by Phase 0 migration
- `backend/src/modules/keys/keyScheduler.js` — replace with the rewritten version below (the old one references `keys` table and assumes `expires_at`)

### 1B. REWRITE `backend/src/modules/keys/keyService.js`

Keep the existing HMAC logic. Only change: remove `KEY_CHARSET` ambiguous characters (already clean). No expiry logic here. Export unchanged: `generateKeyString`, `signKey`, `verifyKeySignature`, `isValidKeyFormat`.

### 1C. REWRITE `backend/src/modules/keys/keyController.js`

Replace entirely with the version below. Key changes:
- All queries target `activation_keys` table (not `keys`)
- Status vocabulary: `available`, `assigned`, `activated`
- `consumeKey` now creates a device record after consuming the key
- Null-safe expiry check removed entirely (no expiry)
- `dealerId = req.user.id` remains correct (dealers log in as users)
- Remove functions: `approveKeyRequest`, `rejectKeyRequest` (admin path handles these)
- Keep functions: `requestKeys`, `assignKeys`, `consumeKey`
- Add function: `getDealerKeys` (GET for dealer to see their pool)
- Add function: `getResellerKeys` (GET for reseller to see their pool)

```
requestKeys     → reseller calls this → inserts into key_requests with status='pending'
assignKeys      → reseller calls this → updates activation_keys SET dealer_id, status='assigned'
consumeKey      → dealer calls this   → updates activation_keys SET status='activated', imei
                                       → then creates device record in devices table
getDealerKeys   → dealer calls this   → SELECT from activation_keys WHERE dealer_id = req.user.id
getResellerKeys → reseller calls this → SELECT from activation_keys WHERE reseller_id = req.user.id
```

**consumeKey request body**:
```
{ keyString, imei, fcmToken, challenge, timestamp }
```
All fields come from the QR payload + the selected key string.

**consumeKey device creation logic** (inside a single DB transaction):

```
0. Validate all fields present. Replay protection:
   a) Timestamp freshness: (Date.now() - timestamp) <= 300000 (5 min)
      If older → return 400 "QR code expired. Ask customer to refresh."
   b) Challenge uniqueness: INSERT INTO used_challenges (challenge, used_at)
      This table has a UNIQUE constraint on challenge.
      If INSERT fails (duplicate) → return 400 "QR code already used."
1. Lock the key row to prevent double-activation race conditions:
   SELECT * FROM activation_keys WHERE key_string = $keyString FOR UPDATE
   If not found → return 404
   If status != 'assigned' → return 409 "Key not available for activation"
   If dealer_id != req.user.id → return 403
   Verify HMAC signature (keyService.verifyKeySignature)
2. Encrypt IMEI and hash it (devices.imei is BYTEA per 002_devices.sql):
   const imeiHash = hashSHA256(plaintextImei)
   const encryptedImei = encryptAES256(plaintextImei)
3. Check IMEI not enrolled: SELECT id FROM devices WHERE imei_hash = $imeiHash
   If found → return 409 "Device already enrolled"
4. Encrypt FCM token (devices.fcm_token is BYTEA per 002_devices.sql):
   const encryptedFcmToken = encryptAES256(fcmToken)
5. Generate TOTP secret: const totpSecretBase32 = base32.encode(crypto.randomBytes(20))
   const encryptedTotp = encryptAES256(totpSecretBase32)
6. INSERT INTO devices (imei, imei_hash, dealer_id, reseller_id, activation_key_id,
     status, lock_level, totp_secret, fcm_token)
   VALUES ($encryptedImei, $imeiHash, $dealerUserId, $resellerUserId, $keyId,
     'enrolled', 'NONE', $encryptedTotp, $encryptedFcmToken)
7. UPDATE activation_keys SET device_id = $newDeviceId, status = 'activated',
     imei = $encryptedImei, imei_hash = $imeiHash, activated_at = NOW()
8. Send FCM CMD_ACTIVATION_CONFIRMED to fcmToken (plaintext, for the API call) with:
   { deviceId, totpSecret: totpSecretBase32 (plaintext, sent once, never stored in HTTP response) }
9. Respond with { deviceId, imei: '***REDACTED***', activatedAt }
```

**Required DB table for challenge replay prevention** (add to 099_unify_schema.sql):
```sql
CREATE TABLE IF NOT EXISTS used_challenges (
  challenge VARCHAR(64) PRIMARY KEY,
  used_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Periodically purge old entries (> 1 hour) via scheduler
```

**Required utility** — add `backend/src/utils/encryption.js`:
```js
const crypto = require('crypto');
const ENCRYPTION_KEY = Buffer.from(process.env.ENCRYPTION_KEY, 'hex'); // 32 bytes
const IV_LENGTH = 16;

function encryptAES256(plaintext) {
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv('aes-256-cbc', ENCRYPTION_KEY, iv);
  return Buffer.concat([iv, cipher.update(plaintext, 'utf8'), cipher.final()]);
}

function decryptAES256(buf) {
  const decipher = crypto.createDecipheriv('aes-256-cbc', ENCRYPTION_KEY, buf.slice(0, IV_LENGTH));
  return decipher.update(buf.slice(IV_LENGTH), undefined, 'utf8') + decipher.final('utf8');
}

function hashSHA256(plaintext) {
  return crypto.createHash('sha256').update(plaintext).digest('hex');
}

module.exports = { encryptAES256, decryptAES256, hashSHA256 };
```

### 1D. REWRITE `backend/src/modules/keys/keyRoutes.js`

```
DELETE:  POST /approve/:requestId   (admin uses /admin/key-requests/:id/approve)
DELETE:  POST /reject/:requestId    (admin uses /admin/key-requests/:id/reject)
KEEP:    POST /request              (reseller — requestKeys)
KEEP:    POST /assign               (reseller — assignKeys)
KEEP:    POST /consume              (dealer   — consumeKey)
ADD:     GET  /my-keys              (dealer   — getDealerKeys, requireRole dealer)
ADD:     GET  /my-pool              (reseller — getResellerKeys, requireRole reseller)
```

### 1E. MODIFY `backend/src/modules/admin/adminDeviceService.js`

Fix all key-related functions. Changes:

1. **`approveKeyRequest`**: Change `status = 'pending'` filter to match `key_requests.status`. The existing code filters `WHERE status = 'pending'` — this is already correct for the canonical schema. Change the generated key INSERT to target `activation_keys` table with columns: `key_string, reseller_id, request_id, hmac_signature, nonce, sig_timestamp, status`. Status is `'available'`. Remove `expires_at`. Call `keyService.generateKeyString()` and `keyService.signKey(keyString, resellerId, nonce)`.

2. **`rejectKeyRequest`**: Change `status = 'pending'` filter — already correct. No other changes needed.

3. **`getKeyRequests`**: Change query to `FROM key_requests`. Already correct.

4. **Fix column name**: Every occurrence of `monthly_key_quota` → change to `monthly_quota`.

5. **Add `getKeyInventory(filters)`**: New function that queries `activation_keys` with JOIN to get reseller name, dealer name. Supports filters: `status`, `reseller_id`, `dealer_id`, `date_from`, `date_to`. Returns paginated results. This is needed for the admin Key Inventory page.

### 1F. MODIFY `backend/src/modules/admin/adminController.js`

Add one new function:
```js
async getKeyInventory(req, res) {
  const filters = {
    status: req.query.status,
    resellerId: req.query.resellerId,
    dealerId: req.query.dealerId,
    dateFrom: req.query.dateFrom,
    dateTo: req.query.dateTo,
    limit: req.query.limit ? parseInt(req.query.limit) : 100,
    offset: req.query.offset ? parseInt(req.query.offset) : 0
  };
  const result = await adminDeviceService.getKeyInventory(filters);
  res.json({ success: true, data: result.keys, total: result.total });
}
```

### 1G. MODIFY `backend/src/modules/admin/adminRoutes.js`

Add one new route (after the existing key-requests routes):
```
GET /key-inventory   → adminController.getKeyInventory
```

With query param validation: `status` in `['available','assigned','activated','revoked']`, `resellerId` UUID, `dealerId` UUID, `dateFrom` ISO8601, `dateTo` ISO8601.

### 1H. REWRITE `backend/src/modules/keys/keyScheduler.js`

The old scheduler expired keys. Since keys have no expiry, remove that job. Keep only the velocity check job, but target `activation_keys` table:

```js
// Velocity check: flag dealers who activate 10+ devices in 24h
SELECT dealer_id, COUNT(*) as count
FROM activation_keys
WHERE activated_at > NOW() - INTERVAL '24 hours' AND status = 'activated'
GROUP BY dealer_id
HAVING COUNT(*) >= 10
```

Log to `audit_log` with action `'VELOCITY_ALERT'`.

### 1I. NEW FILE: `backend/src/modules/unlock-codes/unlockCodeService.js`

```
generateUnlockCode(deviceId, dealerUserId, purpose):
  1. Fetch device from devices table, get totp_secret (decrypt with ENCRYPTION_KEY)
  2. Decode the Base32 string to raw bytes FIRST (Blocker 6: must match Android side)
  3. Generate 6-digit TOTP code using HMAC-SHA1, time step = 1800 seconds
     Standard RFC 6238 algorithm, but with T0=0 and step=1800
  4. Calculate valid_until = NOW() + INTERVAL '90 minutes' (current + next window)
  5. INSERT INTO unlock_codes (device_id, generated_by, purpose, valid_until)
  6. Return { code, validUntil }

TOTP algorithm (Blocker 6 fixed — Base32 decode on both sides):
  const base32 = require('hi-base32')  // npm install hi-base32
  const secretBytes = Buffer.from(base32.decode.asBytes(totpSecretBase32))
  T = Math.floor(Date.now() / 1000 / 1800)  // current time step
  timeBuffer = Buffer.alloc(8); timeBuffer.writeBigInt64BE(BigInt(T))
  HMAC = crypto.createHmac('sha1', secretBytes).update(timeBuffer).digest()
  offset = HMAC[19] & 0xf
  code = ((HMAC[offset] & 0x7f) << 24 | HMAC[offset+1] << 16 | HMAC[offset+2] << 8 | HMAC[offset+3]) % 1000000
  Return as zero-padded 6-digit string

  Android side (OfflineUnlockVerifier.kt) does the same:
  val secretBytes = Base32().decode(base32Secret) // commons-codec
  Then HMAC-SHA1 with secretBytes — BOTH sides use identical byte input.
```

**Required dependency**: `npm install hi-base32` (backend)
**Required dependency**: `implementation("commons-codec:commons-codec:1.16.0")` (Android build.gradle.kts)

### 1J. NEW FILE: `backend/src/modules/unlock-codes/unlockCodeRoutes.js`

```
POST /api/v1/unlock-codes/generate   requireRole('dealer')   → generateUnlockCode
GET  /api/v1/unlock-codes/history/:deviceId  requireRole('admin','dealer') → history
```

Register in `backend/src/routes/index.js`:
```js
router.use('/unlock-codes', require('../modules/unlock-codes/unlockCodeRoutes'));
```

### 1K. NEW FILE: `backend/src/modules/payments/bkashService.js`

```
Functions:
  getBkashToken()          — OAuth token with App Key + App Secret from env vars
  createPayment(amount, merchantRef, callbackUrl)  — POST to Bkash /create
  executePayment(paymentId)                        — POST to Bkash /execute
  queryPayment(paymentId)                          — POST to Bkash /query (verification)
```

All Bkash credentials from env vars: `BKASH_APP_KEY`, `BKASH_APP_SECRET`, `BKASH_USERNAME`, `BKASH_PASSWORD`, `BKASH_BASE_URL`.

### 1L. NEW FILE: `backend/src/modules/payments/paymentController.js`

```
initiatePayment(req, res):
  → Dealer or device calls this with { deviceId, emiId }
  → Fetch device, get dealer's bkash_merchant_number
  → If bkash_enabled=false → return 400 "Dealer has not set up Bkash"
  → Call bkashService.createPayment(amount, merchantRef=deviceId:emiId, callbackUrl)
  → Return { bkashPaymentUrl, paymentId }

bkashWebhook(req, res):
  → Bkash calls this on successful payment
  → Verify transaction with bkashService.queryPayment(paymentId)
  → Match merchantRef to device + emi
  → UPDATE emi_payments: payment_status='completed', bkash_transaction_id, auto_unlocked=true
  → Send FCM CMD_UNLOCK to device
  → Notify dealer app
  → Return 200 to Bkash

manualPayment(req, res):
  → Dealer records cash/bank payment: { deviceId, emiId, amount, method }
  → INSERT into emi_payments with payment_status='completed', recorded_by=req.user.id
  → Then generate TOTP unlock code automatically
  → Return { code, validUntil }

getPaymentHistory(req, res):
  → GET for admin or dealer: payment history for a device
```

### 1M. NEW FILE: `backend/src/modules/payments/paymentRoutes.js`

```
POST /api/v1/payments/initiate         requireRole('dealer')
POST /api/v1/payments/bkash-webhook    (no auth — Bkash calls this directly, verify by signature)
POST /api/v1/payments/manual           requireRole('dealer')
GET  /api/v1/payments/history/:deviceId  requireRole('admin','dealer')
```

Register in `backend/src/routes/index.js` (replace the existing stub `/payments` route).

### 1N. MODIFY `backend/src/modules/emi/emiModel.js` — Canonical Column Cleanup

The existing emiModel queries `emi_payments` using old column names that collide with the canonical schema:

| Old column (code uses) | Canonical column (Phase 0 defines) | Action |
|---|---|---|
| `ep.method` | `ep.payment_method` | Rename in all queries |
| `ep.tx_id` | `ep.transaction_ref` | Rename in all queries |
| `ep.status` | `ep.payment_status` | Rename in all queries |
| old EMI payment schedule FK | `ep.emi_schedule_id` | Rename in all queries |
| `ep.recorded_at` | Keep after Phase 0 guarantees the column exists | Phase 0 adds/backfills from `payment_date` when missing |
| `d.device_name`, `d.model`, `d.brand`, `d.owner_id` | Keep (columns exist in devices) | No change |
| `d.status` (devices) | `d.status` | Keep — canonical devices uses `status`, not `state`. Phase 0 drops the `device_state` enum and normalizes to TEXT `status`. |

Changes:
1. `getFullScheduleWithPayments` (line ~69-84): Replace `ep.method`, `ep.tx_id`, `ep.status` → `ep.payment_method`, `ep.transaction_ref`, `ep.payment_status`
2. `recordPayment` (line ~103-108): INSERT column list `method, tx_id, status` → `payment_method, transaction_ref, payment_status`
3. `recordPayment` (line ~146): UPDATE `status` → `payment_status`
4. All `WHERE status = 'completed'` on `emi_payments` → `WHERE payment_status = 'completed'`
5. `SELECT ... FROM emi_payments WHERE device_id = $1` (line ~87): Keep as-is (wildcard select)

### 1O. MODIFY `backend/src/modules/decoupling/decouplingModel.js` — Canonical Column Cleanup

Same column rename as 1N. Changes:
1. Line ~403: old EMI payment FK → `ep.emi_schedule_id`
2. Line ~403: `ep.status` → `ep.payment_status`
3. Line ~405: join EMI payments through `ep.emi_schedule_id = es.id`
4. Line ~418: final-payment check joins through `ep.emi_schedule_id = es.id`

### 1P. MODIFY `backend/src/modules/admin/adminService.js` — Stop Querying Archived `keys` Table

The `getResellers` function must use the canonical activation-key table. After Phase 0, the legacy key table is archived.

Changes:
1. Replace legacy reseller consumed-key count with `FROM activation_keys WHERE reseller_id = r.id AND status = 'activated'`
2. Replace legacy reseller detail key count with `FROM activation_keys WHERE reseller_id = $1 AND status = 'activated'`
3. Replace `monthly_key_quota` → `monthly_quota` everywhere in adminService.js
4. In `getDashboardStats` (line ~9-10): `devices.status` is correct — canonical devices uses `status` column. Keep as-is.
5. In `setResellerQuota` (line ~209): `monthly_key_quota = $1` → `monthly_quota = $1`
6. In `approveKeyRequest` (line ~777): count monthly approvals from `activation_keys`
7. In `approveKeyRequest` (line ~810): insert generated keys into `activation_keys` with canonical columns

### 1Q. MODIFY `backend/src/modules/admin/adminDeviceService.js` — getKeyRequests FK Fix

The `getKeyRequests` function (line ~623-628) joins `key_requests kr JOIN resellers r ON kr.reseller_id = r.id`. After Phase 0, `key_requests.reseller_id` references `users(id)`, not `resellers(id)`.

Changes:
1. Replace `JOIN resellers r ON kr.reseller_id = r.id` → `JOIN users u2 ON kr.reseller_id = u2.id LEFT JOIN resellers r ON r.user_id = u2.id`
2. Adjust column aliases: `r.name as reseller_name` → `COALESCE(r.business_name, u2.name) as reseller_name`, `r.email as reseller_email` → `u2.email as reseller_email`
3. Replace `r.monthly_key_quota` → `COALESCE(r.monthly_quota, 0) as monthly_quota`

---

## Phase X — Dealer App: Route Convention Audit

The dealer app's Dio `baseURL = EnvConfig.apiBaseUrl` which is the raw server URL (`http://localhost:3000`). It does NOT include `/api/v1`. The backend mounts all routes under `/api/v1` (see `app.use('/api/v1', routes)` in `index.js`).

Therefore **every** dealer app API call must include `/api/v1/...` in the path.

### XA. MODIFY `dealer-app/lib/shared/api/auth_repository.dart`

All paths are missing `/api/v1`:

| Line | Old path | Canonical path |
|---|---|---|
| 19 | `/auth/login` | `/api/v1/auth/login` |
| 45 | `/auth/logout` | `/api/v1/auth/logout` |
| 58 | `/auth/me` | `/api/v1/auth/me` |

### XB. MODIFY `dealer-app/lib/shared/api/api_client.dart`

| Line | Old path | Canonical path |
|---|---|---|
| 62 | `/auth/refresh` | `/api/v1/auth/refresh` |

### XC. MODIFY `dealer-app/lib/shared/services/auth_service.dart`

All paths are missing `/api/v1`:

| Line | Old path | Canonical path |
|---|---|---|
| 40 | `/auth/login` | `/api/v1/auth/login` |
| 70 | `/auth/register/dealer` | `/api/v1/auth/register/dealer` |
| 105 | `/auth/register/reseller` | `/api/v1/auth/register/reseller` |
| 131 | `/auth/logout` | `/api/v1/auth/logout` |
| 138 | `/auth/2fa/setup` | `/api/v1/auth/2fa/setup` |
| 144 | `/auth/2fa/verify` | `/api/v1/auth/2fa/verify` |
| 153 | `/auth/2fa/disable` | `/api/v1/auth/2fa/disable` |
| 163 | legacy auth change-password path | `/api/v1/users/change-password` |
| 177 | `/auth/refresh` | `/api/v1/auth/refresh` |

### XD. MODIFY `dealer-app/lib/shared/constants/constants.dart`

All paths use `/api/` but should be `/api/v1/`:

| Line | Old path | Canonical path |
|---|---|---|
| 4 | `/api/auth/login` | `/api/v1/auth/login` |
| 5 | `/api/auth/register` | `/api/v1/auth/register` |
| 6 | `/api/auth/refresh` | `/api/v1/auth/refresh` |
| 7 | `/api/auth/logout` | `/api/v1/auth/logout` |
| 8 | legacy API auth change-password path | `/api/v1/users/change-password` |
| 9 | `/api/auth/setup-2fa` | `/api/v1/auth/2fa/setup` |
| 10 | `/api/auth/verify-2fa` | `/api/v1/auth/2fa/verify` |
| 11 | `/api/auth/disable-2fa` | `/api/v1/auth/2fa/disable` |

### XE. VERIFY `dealer-app/lib/features/dealer/presentation/dealer_dashboard.dart`

Line 82: `GET /api/v1/dealer/stats` is canonical. Implement backend `router.use('/dealer', require('./dealer'))` in `routes/index.js` with `GET /stats`, `GET /analytics`, and `GET /devices`. Do not redirect this screen to `/dealers/stats`.

### XF. VERIFY `dealer-app/lib/shared/repositories/reseller_repository.dart`

All 16+ paths use `/api/v1/reseller/...`. Backend must provide a dedicated reseller route module mounted at `/reseller` in `routes/index.js`.

Endpoints needed:
```
GET    /api/v1/reseller/stats
GET    /api/v1/reseller/dealers/applications
GET    /api/v1/reseller/dealers
GET    /api/v1/reseller/dealers/applications/:id
GET    /api/v1/reseller/dealers/:id
GET    /api/v1/reseller/dealers/:id/performance
POST   /api/v1/reseller/dealers/applications/:id/approve
POST   /api/v1/reseller/dealers/applications/:id/reject
POST   /api/v1/reseller/dealers/:id/suspend
POST   /api/v1/reseller/dealers/:id/reactivate
POST   /api/v1/reseller/dealers/:id/assign-keys
POST   /api/v1/reseller/keys/request
GET    /api/v1/reseller/keys/requests
GET    /api/v1/reseller/keys/requests/:id
GET    /api/v1/reseller/keys/inventory
GET    /api/v1/reseller/quota
```

---

## Phase X-DB — Device `state` vs `status` Canonical Decision

The base migration (`002_devices.sql`) defines `state device_state` as an ENUM. The active backend code uses `status` (TEXT string). These are different columns.

**Canonical decision**: The canonical column is `status` (TEXT, not ENUM). Phase 0 already normalizes `devices` by:
- Dropping old CHECK constraints on `lock_level`
- Adding `lock_level TEXT NOT NULL DEFAULT 'NONE'`

Phase 0 must explicitly handle the `state` vs `status` collision before any backend code step:

```sql
-- If devices has 'state' column from old migration but code uses 'status':
IF EXISTS (SELECT 1 FROM information_schema.columns
           WHERE table_name = 'devices' AND column_name = 'state')
   AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'devices' AND column_name = 'status') THEN
  -- Rename state → status and cast from enum to TEXT:
  ALTER TABLE devices ALTER COLUMN state TYPE TEXT;
  ALTER TABLE devices RENAME COLUMN state TO status;
ELSIF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'devices' AND column_name = 'state')
   AND EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'devices' AND column_name = 'status') THEN
  -- Both exist: drop old state column (status is the canonical one)
  ALTER TABLE devices DROP COLUMN state;
END IF;

-- Drop device_state enum if no column depends on it:
IF NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE udt_name = 'device_state' AND table_schema = 'public') THEN
  DROP TYPE IF EXISTS device_state;
END IF;
```

---

## Phase 2 — Admin Panel: Active Pages Only

**Rule**: Only modify files that `App.tsx` actually imports. The top-level `ResellersPage.tsx`, `KeyRequestsPage.tsx`, `DashboardPage.tsx`, `AuditLogPage.tsx` etc. are dead code. Do NOT touch them.

### 2A. MODIFY `admin-panel/src/components/admin/nav.ts`

Add Key Inventory to `primaryNavItems`:
```ts
{ name: 'Key Inventory', path: '/key-inventory', icon: Database },
```

Import `Database` from `lucide-react`.

### 2B. MODIFY `admin-panel/src/App.tsx`

Add one import and one route:
```tsx
import KeyInventory from '@/pages/key-inventory';
// Inside the AdminLayout Route:
<Route path="/key-inventory" element={<KeyInventory />} />
```

### 2C. NEW FILE: `admin-panel/src/pages/key-inventory/index.tsx`

Page shows all activation keys across the system.

> **Blocker 7 fix**: Admin axios baseURL is `${VITE_API_BASE_URL}/api/v1`. All API calls from admin pages must use **relative paths** (e.g., `/admin/key-inventory`), NOT absolute paths (e.g., `/api/v1/admin/key-inventory`) which would cause double `/api/v1/api/v1/...`.

API call: `api.get('/admin/key-inventory', { params })`  ← NO `/api/v1` prefix!

UI elements:
- Summary cards at top: Total Keys Generated, Available (reseller pool), Assigned (dealer pool), Activated (consumed), Revoked
- Filter bar: Status dropdown, Reseller dropdown, Dealer dropdown, Date range
- Table columns: Key (masked as `XXXX-XXXX-****-****`), Status badge, Reseller Name, Dealer Name, IMEI (if activated), Created At, Activated At
- Pagination (100 per page)
- Export to CSV button

### 2D. MODIFY `admin-panel/src/pages/resellers/index.tsx`

Add these features to the existing page (do not rewrite, only add):

1. **Create Reseller button** — opens a modal with fields: Business Name, Email, Phone, Password. Calls `api.post('/admin/resellers/create', data)`. On success, show the new reseller's credentials.

2. **Quota usage bar** — under each reseller's name, show a progress bar: `used_keys / monthly_quota`. Color: green if <70%, yellow 70-90%, red >90%.

3. **Set Quota action** — button per row that opens a modal with a number input. Calls `api.post('/admin/resellers/${id}/quota', data)`.

> **API path convention reminder**: Admin panel axios baseURL = `${VITE_API_BASE_URL}/api/v1`. All calls use relative paths WITHOUT `/api/v1` prefix.

4. **Dealer count** — add a `dealer_count` column. The backend's `getResellers` query should add `(SELECT COUNT(*) FROM dealers WHERE reseller_id = r.user_id)` as `dealer_count`.

### 2E. ADD to `backend/src/modules/admin/adminRoutes.js`

```
POST /resellers/create    → adminController.createReseller
```

`createReseller` in `adminDeviceService`:
1. Create user with `role='reseller'`, hashed password
2. Create reseller profile with `user_id`, `business_name`, `monthly_quota=100`
3. Return the new reseller's credentials

---

## Phase 3 — Dealer App (Flutter): Fix Routes and Add Screens

### 3A. MODIFY `dealer-app/lib/features/dealer/reseller_screens/reseller_dealer_list_screen.dart`

The `_GenerateKeysDialog` currently calls the wrong route. Change it:
- Old call: `POST /activation-keys/generate`
- New call: `POST /api/v1/keys/request` with body `{ quantity: int, justification: string }`

> **API path convention**: Dealer app Dio baseURL = `http://localhost:3000` (from `.env`). It does **NOT** include `/api/v1`. Therefore all dealer app calls MUST use full paths like `/api/v1/keys/request`.

Also fix: the dialog should say "Request Keys from Admin" not "Generate Keys" — resellers request, admin approves.

### 3B. MODIFY `dealer-app/lib/features/dealer/reseller_screens/reseller_dealer_list_screen.dart`

The `_AddDealerDialog` creates dealer accounts. Verify it calls `POST /api/v1/dealers` and includes `reseller_id` in the body (the reseller's own user ID from the auth token). If the endpoint does not exist, add it to the backend.

### 3C. NEW FILE: `dealer-app/lib/features/dealer/dealer_screens/device_activation_screen.dart`

This is the screen a dealer uses to activate a customer's phone.

Steps:
1. **Step 1 — Scan QR**: Uses `mobile_scanner` package. Scans the QR shown on the User App. QR payload JSON: `{ "imei": "...", "fcmToken": "...", "challenge": "...", "timestamp": ... }`
2. **Step 2 — Review**: Show scanned IMEI (from QR). Show a dropdown of the dealer's available keys (call `GET /api/v1/keys/my-keys?status=assigned`). Dealer selects which key to use.
3. **Step 3 — Confirm**: Call `POST /api/v1/keys/consume` with `{ keyString, imei, fcmToken, challenge, timestamp }` — all fields from QR + selected key. Show success with the device ID.
4. On success: navigate to the new device's detail screen.

> **API path convention**: Dealer app Dio baseURL = `http://localhost:3000` (NO `/api/v1` prefix). All calls use `/api/v1/...` paths.

### 3D. NEW FILE: `dealer-app/lib/features/dealer/dealer_screens/generate_unlock_code_screen.dart`

Simple screen:
- Input: device selection (search by IMEI or name)
- Purpose selector: "Manual Unlock" or "Cash Payment Confirmed"
- Button: "Generate Code"
- Calls `POST /api/v1/unlock-codes/generate` with `{ deviceId, purpose }`
- Shows the 6-digit code in large text with a countdown timer (90 minutes)
- Tell dealer: "Read this code to the customer over the phone"

### 3E. MODIFY Dealer Dashboard

Add two new action buttons:
- "Activate Device" → navigates to `DeviceActivationScreen`
- "My Keys" → navigates to a simple list page showing `GET /api/v1/keys/my-keys`

---

## Phase 4 — User App (Kotlin): SIM Toolkit Stealth + Hidden Activation

### 4A. MODIFY `user-app/app/src/main/res/values/strings.xml`

```xml
<string name="app_name">SIM Toolkit</string>
<string name="notification_channel_name">System Service</string>
<string name="notification_channel_desc">Background system service</string>
<string name="service_running_text">System service running</string>
```

Remove all references to "EMI Locker" from this file.

### 4B. MODIFY the main Activity/Fragment shown before activation

Show a fake SIM Toolkit UI:
- Title: "SIM Toolkit"
- Grid of icons: "SIM Info", "Network Info", "Balance Check", "Data Usage", "Roaming", "Settings"
- None of these do anything meaningful — they show generic info dialogs
- **Secret gesture**: long-press on the version text at the bottom for 5 seconds → navigate to `ActivationScreen`

### 4C. NEW FILE: `ActivationScreen.kt` + `ActivationViewModel.kt`

The hidden activation screen. Only reachable via the secret gesture.

`ActivationViewModel` (Blocker 4 fixed — includes FCM token):
- Gets device IMEI via `TelephonyManager` (requires `READ_PHONE_STATE` permission)
- Gets FCM token: `val fcmToken = FirebaseMessaging.getInstance().token.await()`
- Generates a challenge nonce: `UUID.randomUUID().toString()`
- QR payload: `{ "imei": imei, "fcmToken": fcmToken, "challenge": nonce, "timestamp": System.currentTimeMillis() }`
- QR auto-refreshes every 60 seconds (new nonce + new timestamp each refresh)
- State machine: `UNACTIVATED` → `SHOWING_QR` → `WAITING` → `ACTIVATED`
- Listens for FCM `CMD_ACTIVATION_CONFIRMED` message

`ActivationScreen`:
- Shows a QR code (use `zxing-android-embedded` or `compose-qr-code` library)
- Shows countdown timer for QR refresh
- Shows status text: "Waiting for dealer to scan..."
- On `ACTIVATED` state: shows "Setup complete. Your device is registered." → then navigates back to fake SIM Toolkit UI

### 4D. MODIFY `EmiLockerFcmService.kt`

Add command handler:
```kotlin
"CMD_ACTIVATION_CONFIRMED" -> {
  val deviceId = data["deviceId"] ?: return
  val totpSecret = data["totpSecret"] ?: return  // base32 plaintext, store encrypted
  // Save to EncryptedSharedPreferences:
  prefs.edit()
    .putString("device_id", deviceId)
    .putString("totp_secret", totpSecret)
    .putBoolean("is_activated", true)
    .apply()
  // Start enforcement service:
  startService(Intent(this, EmiLockerService::class.java))
  // Broadcast to ActivationViewModel to update state:
  sendBroadcast(Intent("com.android.simtoolkit.ACTIVATION_CONFIRMED"))
}
```

### 4E. MODIFY `OverlayManager.kt` — Three additions

**Addition 1: Call → Retake Screen**
```kotlin
// Use TelephonyCallback (API 31+) or PhoneStateListener (API < 31)
// When call state transitions to IDLE (call ended):
//   → call showFullLockOverlay() immediately
// Register this listener when lock overlay appears, unregister when overlay is removed
```

**Addition 2: Pay Now button**
```kotlin
// "Pay Now" button opens a BottomSheet with two options:
// Option A — Online Portal:
//   Open CustomTabsIntent pointing to: "$API_BASE_URL/pay/$deviceId"
// Option B — Dealer QR Code:
//   Fetch dealer's Bkash QR from backend, show as bitmap
//   Label the QR with the exact EMI amount due
// After payment, backend webhook auto-unlocks via FCM CMD_UNLOCK
```

**Addition 3: Enter Unlock Code field**
```kotlin
// Collapsible section: "Have an unlock code?" 
// Expands to reveal: 6-digit PIN input + "Unlock" button
// On submit: call OfflineUnlockVerifier.verify(code)
// If valid → send broadcast to dismiss overlay, save LockState=NORMAL
// If invalid → show "Wrong code". After 5 failures → 10-min cooldown
// Also: show a persistent notification with direct-reply action so user
//   can enter code from notification shade without opening any app
```

### 4F. NEW FILE: `OfflineUnlockVerifier.kt`

```kotlin
object OfflineUnlockVerifier {
  fun verify(inputCode: String, context: Context): Boolean {
    val prefs = EncryptedSharedPreferences.create(...)
    val totpSecret = prefs.getString("totp_secret", null) ?: return false
    val secretBytes = Base32().decode(totpSecret)
    // Check current window and ±1 window (each window = 1800 seconds)
    val currentStep = System.currentTimeMillis() / 1000L / 1800L
    for (step in (currentStep - 1)..(currentStep + 1)) {
      val code = computeTotp(secretBytes, step)
      if (code == inputCode) return true
    }
    return false
  }

  private fun computeTotp(secret: ByteArray, step: Long): String {
    val data = ByteBuffer.allocate(8).putLong(step).array()
    val mac = Mac.getInstance("HmacSHA1")
    mac.init(SecretKeySpec(secret, "HmacSHA1"))
    val hash = mac.doFinal(data)
    val offset = hash[19].toInt() and 0xf
    val code = ((hash[offset].toInt() and 0x7f) shl 24 or
                (hash[offset+1].toInt() and 0xff) shl 16 or
                (hash[offset+2].toInt() and 0xff) shl 8 or
                (hash[offset+3].toInt() and 0xff)) % 1000000
    return code.toString().padStart(6, '0')
  }
}
```

---

## Phase 5 — Environment Variables (Required, Add to `.env`)

```env
# Existing (keep)
JWT_SECRET=
HMAC_SECRET=          # Used for activation key HMAC signatures

# New — add these
ENCRYPTION_KEY=       # 32-byte hex key for AES-256 encryption of totp_secret in DB
BKASH_APP_KEY=
BKASH_APP_SECRET=
BKASH_USERNAME=
BKASH_PASSWORD=
BKASH_BASE_URL=       # Bkash sandbox or production API base URL
API_BASE_URL=         # e.g., https://api.yourdomain.com — used in User App payment URL
```

---

## Phase 6 — Hosted Payment Page

### 6A. NEW ROUTE in `backend/src/index.js` (NOT in `routes/index.js`)

> **Blocker 8 fix**: The payment page is a public HTML page, NOT an API endpoint.
> `routes/index.js` is mounted at `/api/v1`. If we add the route there, the URL becomes
> `/api/v1/pay/:deviceId` but the User App opens `$API_BASE_URL/pay/$deviceId`.
> Solution: mount OUTSIDE the `/api/v1` router, directly on the Express `app` object.

In `backend/src/index.js`, BEFORE the `app.use('/api/v1', routes)` line:
```js
// Public payment page — mounted outside /api/v1 (Blocker 8)
app.get('/pay/:deviceId', require('./modules/payments/paymentPageController').renderPaymentPage);
```

User App opens: `"${BuildConfig.API_BASE_URL}/pay/${deviceId}"` → `http://localhost:3000/pay/abc-123` ✅

No auth required — this is opened by the user's phone.

`renderPaymentPage`:
1. Fetch device + active EMI installment + dealer's Bkash merchant number
2. Render an HTML page (Express `res.send(html)`) showing:
   - "Payment Due: ৳X,XXX"
   - Dealer name
   - A "Pay with Bkash" button that calls `POST /api/v1/payments/initiate`
   - On success: redirect to the Bkash payment URL
3. After Bkash webhook confirms payment → device auto-unlocks via FCM

---

## What Codex Must NOT Touch (Preserve As-Is)

These are working correctly. Do not modify (unless explicitly listed in a Phase above):

- `backend/src/modules/admin/adminRoutes.js` — (except the two additions in Phase 1G and 2E)
- `backend/src/middleware/auth.js` — JWT auth is working
- `backend/src/middleware/rbac.js` — Role checking is working
- `backend/src/middleware/errorHandler.js` — Error handling is fine
- `backend/src/modules/lock/` — Lock module is working
- `backend/src/modules/location/` — Location module is working
- `backend/src/modules/decoupling/decouplingRoutes.js` — Routes are working (BUT `decouplingModel.js` needs column rename per Phase 1O)
- `backend/src/modules/emi/emiRoutes.js` — Routes are working (BUT `emiModel.js` needs column rename per Phase 1N)
- `backend/src/modules/fraud/` — Fraud detection is working
- `admin-panel/src/pages/dashboard/index.tsx` — Dashboard is working
- `admin-panel/src/pages/devices/index.tsx` — Devices page is working
- `admin-panel/src/pages/audit-log/index.tsx` — Audit log is working
- `admin-panel/src/pages/security-events/index.tsx` — Security events working
- `admin-panel/src/api/axios.ts` — API client is correctly configured
- `admin-panel/src/store/authStore.ts` — Auth state is working
- All dead top-level `*Page.tsx` files — leave them, do not modify, do not delete

---

## Implementation Order for Codex

Run these in strict order. Each phase depends on the previous.

```
1. Run 099_unify_schema.sql on the database
2. Rewrite keyController.js (Phase 1C)
3. Rewrite keyRoutes.js (Phase 1D)
4. Rewrite keyScheduler.js (Phase 1H)
5. Modify adminDeviceService.js (Phase 1E)
6. Modify adminController.js (Phase 1F)
7. Modify adminRoutes.js (Phase 1G + 2E)
8. Create unlockCodeService.js + unlockCodeRoutes.js (Phase 1I + 1J)
9. Create bkashService.js (Phase 1K)
10. Create paymentController.js + paymentRoutes.js (Phase 1L + 1M)
11. Modify routes/index.js to register new routes
12. Admin Panel — nav.ts, App.tsx, key-inventory page (Phase 2A + 2B + 2C)
13. Admin Panel — resellers page additions (Phase 2D)
14. Dealer App — fix reseller key request route (Phase 3A)
15. Dealer App — device activation screen (Phase 3C)
16. Dealer App — unlock code screen (Phase 3D)
17. Dealer App — dashboard additions (Phase 3E)
18. User App — strings.xml (Phase 4A)
19. User App — fake SIM Toolkit UI + secret gesture (Phase 4B)
20. User App — ActivationScreen + ActivationViewModel (Phase 4C)
21. User App — FCM handler additions (Phase 4D)
22. User App — OverlayManager additions (Phase 4E)
23. User App — OfflineUnlockVerifier (Phase 4F)
24. Backend — hosted payment page route (Phase 6A)
25. Backend — emiModel.js canonical column rename (Phase 1N)
26. Backend — decouplingModel.js canonical column rename (Phase 1O)
27. Backend — adminService.js stop querying `keys` table (Phase 1P)
28. Backend — adminDeviceService.js getKeyRequests FK fix (Phase 1Q)
29. Dealer App — auth_repository.dart add /api/v1 prefix (Phase XA)
30. Dealer App — api_client.dart add /api/v1 prefix (Phase XB)
31. Dealer App — auth_service.dart add /api/v1 prefix (Phase XC)
32. Dealer App — constants.dart fix /api/ → /api/v1/ (Phase XD)
33. Dealer App — dealer_dashboard.dart verify /dealer route (Phase XE)
34. Backend — add resellerRoutes.js for /reseller/* endpoints (Phase XF)
35. Backend — add devices state→status normalization (Phase X-DB)
```

---

## Security Checklist (Codex must verify each before completing)

- [ ] `HMAC_SECRET` is never logged or returned in any API response
- [ ] `ENCRYPTION_KEY` is never logged or returned in any API response
- [ ] `totp_secret` is always AES-256 encrypted before INSERT, decrypted only in memory for TOTP generation
- [ ] The Bkash webhook endpoint verifies the transaction with Bkash API before acting on it (no spoofing)
- [ ] `consumeKey` uses `SELECT ... FOR UPDATE` on the key row to prevent double-activation race conditions (NOT `SKIP LOCKED` — a specific key must block, not skip)
- [ ] All admin routes require `requireVerified2FA` (already in place via `adminRoutes.js` middleware)
- [ ] The hosted payment page (`/pay/:deviceId`) does not expose any sensitive device info in HTML source
- [ ] FCM `CMD_ACTIVATION_CONFIRMED` only triggers enforcement if `is_activated` is not already true (idempotent)
- [ ] The secret gesture for the hidden activation screen has no visual indicator — no button, no label
- [ ] `OfflineUnlockVerifier` rate-limits: 5 failed attempts → 10-minute lockout stored in `EncryptedSharedPreferences`
- [ ] At 1M keys/6 months scale: confirm the composite indexes on `activation_keys(reseller_id, status)` and `(dealer_id, status)` are created (they are in Phase 0)
