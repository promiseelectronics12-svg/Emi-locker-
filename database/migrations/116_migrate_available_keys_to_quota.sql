-- Migration 116: promote orphaned available key rows into reseller quota columns
-- Required after migration to on-demand key generation (migration 114).
-- Pre-existing activation_keys with status='available' were generated under the
-- old batch model. They are now invisible to the UI which reads quota columns.
-- This migration moves those counts into quota columns and removes the orphaned rows.

UPDATE resellers r
SET
  quota_standard = quota_standard + sub.std,
  quota_premium  = quota_premium  + sub.prem,
  quota_vip      = quota_vip      + sub.vip,
  updated_at     = NOW()
FROM (
  SELECT reseller_id,
    COUNT(*) FILTER (WHERE tier = 'standard') AS std,
    COUNT(*) FILTER (WHERE tier = 'premium')  AS prem,
    COUNT(*) FILTER (WHERE tier = 'vip')      AS vip
  FROM activation_keys
  WHERE status = 'available' AND dealer_id IS NULL
  GROUP BY reseller_id
) sub
WHERE r.id = sub.reseller_id;

DELETE FROM activation_keys WHERE status = 'available' AND dealer_id IS NULL;
