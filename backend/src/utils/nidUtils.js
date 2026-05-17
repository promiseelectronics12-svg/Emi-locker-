const crypto = require('crypto');

// NID_PLATFORM_SECRET must be a stable 32+ byte random hex string.
// Set it in Render env vars before deploying enrollment changes.
// NEVER rotate: all existing nid_hmac lookups break on rotation.
// If secret is missing in production, enrollment will fail-fast.

function getNidSecret() {
  const secret = process.env.NID_PLATFORM_SECRET;
  if (!secret) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('NID_PLATFORM_SECRET must be set in production');
    }
    // Dev fallback — never matches production hashes
    return 'dev-nid-secret-do-not-use-in-production';
  }
  return secret;
}

/**
 * Normalizes NID before hashing: uppercase, trim whitespace, remove spaces.
 * Consistent normalization prevents duplicate hashes for the same NID
 * entered with different formatting.
 */
function normalizeNid(nid) {
  return String(nid || '').trim().toUpperCase().replace(/\s+/g, '');
}

/**
 * Returns HMAC-SHA256(NID_PLATFORM_SECRET, normalize(nid)) as hex.
 * Use this for all new NID writes (nid_hash_version = 2).
 */
function hashNid(nid) {
  const normalized = normalizeNid(nid);
  if (!normalized) throw new Error('NID is required');
  return crypto
    .createHmac('sha256', getNidSecret())
    .update(normalized)
    .digest('hex');
}

/**
 * Returns the HMAC hex for a NID — same as hashNid, exposed as alias
 * for lookup queries: WHERE nid_hmac = lookupNid(rawNid)
 */
function lookupNid(nid) {
  return hashNid(nid);
}

module.exports = { hashNid, lookupNid, normalizeNid };
