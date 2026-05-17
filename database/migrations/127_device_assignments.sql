-- Migration 127: device_assignments — ownership period separation
--
-- Separates the physical device record from customer ownership periods.
-- A device can have multiple sequential assignments (original customer,
-- then resold to new customer). All audit tables gain a nullable
-- assignment_id so history can be scoped to a specific ownership period.
--
-- Idempotent-safe: can be re-run without error.

BEGIN;

-- ── 1. device_assignments table ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS device_assignments (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id       UUID        NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
  customer_id     UUID        REFERENCES users(id) ON DELETE SET NULL,
  dealer_id       UUID        REFERENCES dealers(id) ON DELETE SET NULL,
  emi_schedule_id UUID        REFERENCES emi_schedules(id) ON DELETE SET NULL,
  status          VARCHAR(20) NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'closed', 'reconnected', 'resold')),
  assigned_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at       TIMESTAMPTZ,
  close_reason    VARCHAR(30)
                  CHECK (close_reason IN (
                    'decoupled', 'resold', 'reconnected', 'admin_override'
                  )),
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One active assignment per device — enforced at DB level
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_assignments_one_active
  ON device_assignments(device_id)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_device_assignments_device
  ON device_assignments(device_id, status);

CREATE INDEX IF NOT EXISTS idx_device_assignments_customer
  ON device_assignments(customer_id, status);

CREATE INDEX IF NOT EXISTS idx_device_assignments_dealer
  ON device_assignments(dealer_id, assigned_at DESC);

-- ── 2. Backfill active assignments from current device state ─────────────────
-- Creates one 'active' assignment for every device that has an owner
-- and is not decoupled/decommissioned. Idempotent via ON CONFLICT DO NOTHING
-- on the partial unique index.

INSERT INTO device_assignments (
  device_id,
  customer_id,
  dealer_id,
  emi_schedule_id,
  status,
  assigned_at
)
SELECT
  d.id,
  d.owner_id,
  dl.id,
  es.id,
  'active',
  COALESCE(d.enrolled_at, d.created_at)
FROM devices d
LEFT JOIN dealers dl ON dl.id = d.dealer_id
LEFT JOIN emi_schedules es
  ON es.device_id = d.id AND es.status = 'active'
WHERE d.owner_id IS NOT NULL
  AND d.status NOT IN ('decoupled', 'decommissioned', 'disabled', 'pending')
  AND dl.id IS NOT NULL
  -- Skip if assignment already exists for this device
  AND NOT EXISTS (
    SELECT 1 FROM device_assignments da
    WHERE da.device_id = d.id AND da.status = 'active'
  );

-- Closed assignments for decoupled devices (no active emi_schedule)
INSERT INTO device_assignments (
  device_id,
  customer_id,
  dealer_id,
  status,
  assigned_at,
  closed_at,
  close_reason
)
SELECT
  d.id,
  d.owner_id,
  dl.id,
  'closed',
  COALESCE(d.enrolled_at, d.created_at),
  d.updated_at,
  'decoupled'
FROM devices d
LEFT JOIN dealers dl ON dl.id = d.dealer_id
WHERE d.status = 'decoupled'
  AND d.owner_id IS NOT NULL
  AND dl.id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM device_assignments da
    WHERE da.device_id = d.id
  );

-- ── 3. Add assignment_id to audit tables (nullable for backcompat) ────────────

ALTER TABLE device_history
  ADD COLUMN IF NOT EXISTS assignment_id UUID
    REFERENCES device_assignments(id) ON DELETE SET NULL;

ALTER TABLE sim_events
  ADD COLUMN IF NOT EXISTS assignment_id UUID
    REFERENCES device_assignments(id) ON DELETE SET NULL;

ALTER TABLE location_reports
  ADD COLUMN IF NOT EXISTS assignment_id UUID
    REFERENCES device_assignments(id) ON DELETE SET NULL;

-- Indexes for assignment-scoped history queries
CREATE INDEX IF NOT EXISTS idx_device_history_assignment
  ON device_history(assignment_id, created_at DESC)
  WHERE assignment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sim_events_assignment
  ON sim_events(assignment_id, detected_at DESC)
  WHERE assignment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_location_reports_assignment
  ON location_reports(assignment_id, created_at DESC)
  WHERE assignment_id IS NOT NULL;

-- ── 4. Backfill assignment_id on existing history rows ───────────────────────
-- Links existing history to the assignment for that device.
-- For devices with only one assignment (typical), this is unambiguous.
-- For decoupled+reassigned devices (rare pre-migration), links to closed.

UPDATE device_history dh
SET assignment_id = da.id
FROM device_assignments da
WHERE dh.device_id = da.device_id
  AND dh.assignment_id IS NULL
  AND (
    da.status = 'active'
    OR (
      da.status = 'closed'
      AND da.closed_at >= dh.created_at
    )
  );

UPDATE sim_events se
SET assignment_id = da.id
FROM device_assignments da
WHERE se.device_id = da.device_id
  AND se.assignment_id IS NULL
  AND (
    da.status = 'active'
    OR (
      da.status = 'closed'
      AND da.closed_at >= se.detected_at
    )
  );

UPDATE location_reports lr
SET assignment_id = da.id
FROM device_assignments da
WHERE lr.device_id = da.device_id
  AND lr.assignment_id IS NULL
  AND (
    da.status = 'active'
    OR (
      da.status = 'closed'
      AND da.closed_at >= lr.created_at
    )
  );

COMMIT;
