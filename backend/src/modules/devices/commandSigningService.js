const crypto = require('crypto');
const logger = require('../../utils/logger');
const firebaseService = require('./firebaseService');
const kmsSigningService = require('./kmsSigningService');

class CommandSigningService {
  constructor() {
    this.commandExpiryMs = 5 * 60 * 1000;
  }

  generateNonce() {
    return crypto.randomBytes(16).toString('hex');
  }

  generateTimestamp() {
    return Date.now();
  }

  isTimestampValid(timestamp) {
    const now = Date.now();
    const age = now - timestamp;
    return age >= 0 && age <= this.commandExpiryMs;
  }

  async signPayload(imei, timestamp, nonce, payload, hardwareBinding = {}) {
    if (!imei || !timestamp || !nonce || !payload) {
      throw new Error('IMEI, timestamp, nonce, and payload are required for signing');
    }

    const signingPayload = {
      imei,
      timestamp,
      nonce,
      message: payload,
      ...hardwareBinding
    };

    const result = await kmsSigningService.sign(signingPayload);

    return {
      signature: result.signature,
      timestamp,
      nonce,
      algorithm: result.algorithm || 'RS256',
      provider: result.provider,
      keyId: result.keyId
    };
  }

  async createSignedCommand(deviceId, commandType, payload, imei, hardwareBinding = {}) {
    const nonce = this.generateNonce();
    const timestamp = this.generateTimestamp();

    const commandPayload = {
      deviceId,
      commandType,
      payload,
      imei,
      ...hardwareBinding
    };

    const signingResult = await this.signPayload(imei, timestamp, nonce, commandPayload, hardwareBinding);

    const signedCommand = {
      ...commandPayload,
      ...signingResult,
      createdAt: new Date().toISOString(),
      expiresAt: new Date(timestamp + this.commandExpiryMs).toISOString()
    };

    await firebaseService.writeCommandHistory(deviceId, {
      type: commandType,
      signedCommand,
      status: 'signed'
    });

    return signedCommand;
  }

  async createAndStoreSignedCommand(deviceId, commandType, payload, imei, hardwareBinding = {}) {
    const signedCommand = await this.createSignedCommand(deviceId, commandType, payload, imei, hardwareBinding);

    await firebaseService.writeSignedCommand(deviceId, signedCommand);

    return signedCommand;
  }

  async verifySignedCommand(deviceId, signedCommand) {
    const { imei, timestamp, nonce, payload, signature } = signedCommand;

    if (!this.isTimestampValid(timestamp)) {
      throw new Error('Command has expired');
    }

    const commandPayload = {
      deviceId,
      payload
    };

    const signingPayload = {
      imei,
      timestamp,
      nonce,
      message: commandPayload
    };

    const isValid = await kmsSigningService.verifySignature(signingPayload, signature, {
      provider: signedCommand.provider,
      keyId: signedCommand.keyId
    });

    if (!isValid) {
      logger.warn(`Command signature verification failed for device: ${deviceId}`);
      throw new Error('Command signature verification failed');
    }

    return true;
  }
}

module.exports = new CommandSigningService();