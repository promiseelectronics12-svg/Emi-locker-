const crypto = require('crypto');

const { HMAC_SECRET } = process.env;
const { HSM_KEY } = process.env;

if (!HMAC_SECRET && !HSM_KEY) {
  throw new Error(
    'HMAC_SECRET or HSM_KEY environment variable must be set - command signatures cannot be securely generated without it'
  );
}

function signCommand(data) {
  const hmacKey = HSM_KEY || HMAC_SECRET;
  const payload = JSON.stringify(data);

  return crypto.createHmac('sha256', hmacKey).update(payload).digest('hex');
}

function verifySignature(data, signature) {
  const expectedSignature = signCommand(data);
  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expectedSignature));
}

function generateCommandId() {
  return crypto.randomBytes(16).toString('hex');
}

function createSignedLockCommand(deviceId, lockLevel, imei, serial, soc_model) {
  const timestamp = new Date().toISOString();
  const nonce = crypto.randomBytes(16).toString('hex');
  const commandData = {
    deviceId,
    lockLevel,
    command: lockLevel >= 7 ? 'FULL_LOCK' : lockLevel >= 3 ? 'REMINDER_MODE' : 'LOCK',
    timestamp,
    nonce,
    serverId: process.env.SERVER_ID || 'server-001',
    imei,
    serial,
    soc_model
  };

  return {
    ...commandData,
    signature: signCommand(commandData)
  };
}

function createSignedUnlockCommand(deviceId, expiryHours = 48, imei, serial, soc_model) {
  const timestamp = new Date().toISOString();
  const expiry = new Date(Date.now() + expiryHours * 60 * 60 * 1000).toISOString();
  const nonce = crypto.randomBytes(16).toString('hex');

  const commandData = {
    deviceId,
    command: 'UNLOCK',
    timestamp,
    expiry,
    nonce,
    serverId: process.env.SERVER_ID || 'server-001',
    imei,
    serial,
    soc_model
  };

  return {
    ...commandData,
    signature: signCommand(commandData)
  };
}

function verifySignedCommand(command) {
  const { signature, ...data } = command;
  return verifySignature(data, signature);
}

module.exports = {
  signCommand,
  verifySignature,
  generateCommandId,
  createSignedLockCommand,
  createSignedUnlockCommand,
  verifySignedCommand
};
