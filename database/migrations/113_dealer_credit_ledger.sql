-- Migration 113: dealer credit ledger
-- Tracks key assignments from reseller to dealer as credit events.
-- Each assignment creates a ledger entry the reseller can mark settled.

CREATE TABLE IF NOT EXISTS dealer_credit_ledger (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reseller_id UUID NOT NULL REFERENCES resellers(id),
  dealer_id   UUID NOT NULL,
  keys_quantity INTEGER NOT NULL,
  tier        TEXT NOT NULL DEFAULT 'standard'
                CHECK (tier IN ('standard', 'premium', 'vip')),
  notes       TEXT,
  due_date    DATE,
  settled_at  TIMESTAMPTZ,
  status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'settled')),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dcl_reseller ON dealer_credit_ledger(reseller_id);
CREATE INDEX IF NOT EXISTS idx_dcl_dealer   ON dealer_credit_ledger(dealer_id);
CREATE INDEX IF NOT EXISTS idx_dcl_status   ON dealer_credit_ledger(reseller_id, status);
