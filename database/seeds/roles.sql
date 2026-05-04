-- Seed: roles.sql
-- Description: Initial admin account and default role setup

-- NOTE: The password hash below is a PLACEHOLDER.
-- Before deployment, generate a real bcrypt hash of 'ChangeMe123!' using:
--   php -r "echo password_hash('ChangeMe123!', PASSWORD_BCRYPT, ['cost' => 12]);"
-- The well-known hash `$2b$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi`
-- is the Laravel default test hash for 'password', NOT 'ChangeMe123!'.

-- Note: email and phone are stored as BYTEA (AES-256 encrypted at rest)
-- The values below are placeholder hex — application must encrypt before insert
-- Run via application seed script that handles encryption

-- This seed file is a TEMPLATE. Use the application's seed runner to execute
-- because email/phone/totp_secret require AES-256 encryption at application level.

-- Application seed script should call:
-- INSERT INTO users (id, email, phone, role, password_hash, totp_secret, status)
-- VALUES (
--     '00000000-0000-0000-0000-000000000001',
--     encrypt_aes256('admin@localhost', <ENCRYPTION_KEY>),
--     encrypt_aes256('+00000000000', <ENCRYPTION_KEY>),
--     'admin',
--     -- TODO: Generate real bcrypt hash of 'ChangeMe123!' before deployment
--     '$2b$12$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
--     NULL,
--     'active'
-- );

-- For direct SQL seed (development only, no encryption):
INSERT INTO users (id, email, phone, role, password_hash, status)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    -- Plaintext placeholder — encrypt in production
    decode('61646d696e406c6f63616c686f7374', 'hex'),  -- 'admin@localhost'
    decode('2b3030303030303030303030', 'hex'),          -- '+00000000000'
    'admin',
    -- TODO: Generate real bcrypt hash of 'ChangeMe123!' before deployment
    '$2b$12$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
    'active'
)
ON CONFLICT (id) DO NOTHING;