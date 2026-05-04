const crypto = require('crypto');
const db = require('../../config/database');
const logger = require('../../utils/logger');

class HardwareBindingService {
  constructor() {
    this.hashAlgorithm = 'sha256';
    this.iterations = 10000;
    this.keyLength = 32;
    this.saltLength = 16;
  }

  generateSalt() {
    return crypto.randomBytes(this.saltLength).toString('hex');
  }

  createHardwareHash(imei, serialNumber, socId) {
    if (!imei || !serialNumber || !socId) {
      throw new Error('IMEI, serial number, and SoC ID are required for hardware binding');
    }

    const cleanImei = this.sanitizeHardwareId(imei);
    const cleanSerial = this.sanitizeHardwareId(serialNumber);
    const cleanSocId = this.sanitizeHardwareId(socId);

    if (!this.validateImei(cleanImei)) {
      throw new Error('Invalid IMEI format');
    }

    const combinedData = `${cleanImei}:${cleanSerial}:${cleanSocId}`;
    const salt = this.generateSalt();

    const hash = crypto.pbkdf2Sync(
      combinedData,
      salt,
      this.iterations,
      this.keyLength,
      this.hashAlgorithm
    );

    return {
      hash: hash.toString('hex'),
      salt,
      imei: cleanImei,
      serialNumber: cleanSerial,
      socId: cleanSocId
    };
  }

  verifyHardwareHash(storedHash, salt, imei, serialNumber, socId) {
    if (!storedHash || !salt || !imei || !serialNumber || !socId) {
      return false;
    }

    const cleanImei = this.sanitizeHardwareId(imei);
    const cleanSerial = this.sanitizeHardwareId(serialNumber);
    const cleanSocId = this.sanitizeHardwareId(socId);

    const combinedData = `${cleanImei}:${cleanSerial}:${cleanSocId}`;

    const hash = crypto.pbkdf2Sync(
      combinedData,
      salt,
      this.iterations,
      this.keyLength,
      this.hashAlgorithm
    );

    const computedHash = hash.toString('hex');

    return this.safeCompare(computedHash, storedHash);
  }

  sanitizeHardwareId(id) {
    if (typeof id !== 'string') {
      return String(id);
    }
    return id.trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  }

  safeCompare(a, b) {
    try {
      const bufA = Buffer.from(a, 'utf8');
      const bufB = Buffer.from(b, 'utf8');
      if (bufA.length !== bufB.length) {
        return false;
      }
      return crypto.timingSafeEqual(bufA, bufB);
    } catch (error) {
      return false;
    }
  }

  validateImei(imei) {
    const imeiRegex = /^\d{15}$/;
    if (!imeiRegex.test(imei)) {
      return false;
    }

    let sum = 0;
    let isEven = false;

    for (let i = imei.length - 1; i >= 0; i--) {
      let digit = parseInt(imei[i], 10);

      if (isEven) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }

      sum += digit;
      isEven = !isEven;
    }

    return sum % 10 === 0;
  }

  async storeHardwareBinding(deviceId, imei, serialNumber, socId) {
    const hardwareData = this.createHardwareHash(imei, serialNumber, socId);

    await db.query(
      `UPDATE devices
       SET hardware_hash = $1,
           hardware_salt = $2,
           hardware_imei_encrypted = $3,
           hardware_serial_encrypted = $4,
           hardware_soc_encrypted = $5,
           hardware_bound_at = NOW(),
           updated_at = NOW()
       WHERE id = $6`,
      [
        hardwareData.hash,
        hardwareData.salt,
        this.encryptForStorage(hardwareData.imei),
        this.encryptForStorage(hardwareData.serialNumber),
        this.encryptForStorage(hardwareData.socId),
        deviceId
      ]
    );

    logger.info(`Hardware binding stored for device: ${deviceId}`);

    return {
      deviceId,
      hash: hardwareData.hash,
      salt: hardwareData.salt,
      boundAt: new Date()
    };
  }

  async verifyDeviceHardware(deviceId, imei, serialNumber, socId) {
    const result = await db.query(
      `SELECT hardware_hash, hardware_salt, hardware_imei_encrypted,
              hardware_serial_encrypted, hardware_soc_encrypted, hardware_bound_at
       FROM devices WHERE id = $1`,
      [deviceId]
    );

    if (result.rows.length === 0) {
      throw new Error('Device not found');
    }

    const device = result.rows[0];

    if (!device.hardware_hash || !device.hardware_salt) {
      throw new Error('Device has not been hardware bound');
    }

    const decryptedImei = this.decryptFromStorage(device.hardware_imei_encrypted);
    const decryptedSerial = this.decryptFromStorage(device.hardware_serial_encrypted);
    const decryptedSoc = this.decryptFromStorage(device.hardware_soc_encrypted);

    const cleanImei = this.sanitizeHardwareId(imei);
    const cleanSerial = this.sanitizeHardwareId(serialNumber);
    const cleanSocId = this.sanitizeHardwareId(socId);

    const isImeiMatch = this.safeCompare(cleanImei, decryptedImei);
    const isSerialMatch = this.safeCompare(cleanSerial, decryptedSerial);
    const isSocMatch = this.safeCompare(cleanSocId, decryptedSoc);

    if (!isImeiMatch || !isSerialMatch || !isSocMatch) {
      logger.warn(`Hardware identifier mismatch for device: ${deviceId}`);
      await this.logSecurityEvent('HARDWARE_BINDING_MISMATCH', { deviceId, imei: cleanImei });
      return {
        isValid: false,
        deviceId,
        message: 'Hardware binding verification failed'
      };
    }

    const isValid = this.verifyHardwareHash(
      device.hardware_hash,
      device.hardware_salt,
      cleanImei,
      cleanSerial,
      cleanSocId
    );

    if (!isValid) {
      logger.warn(`Hardware verification failed for device: ${deviceId}`);
      await this.logSecurityEvent('HARDWARE_BINDING_INVALID', { deviceId, imei: cleanImei });
      return {
        isValid: false,
        deviceId,
        message: 'Hardware binding verification failed'
      };
    }

    logger.info(`Hardware verification successful for device: ${deviceId}`);

    return {
      isValid: true,
      deviceId,
      boundAt: device.hardware_bound_at
    };
  }

  async checkHardwareBindingExists(deviceId) {
    const result = await db.query(
      `SELECT hardware_hash, hardware_bound_at FROM devices WHERE id = $1`,
      [deviceId]
    );

    if (result.rows.length === 0) {
      return { bound: false, reason: 'Device not found' };
    }

    const device = result.rows[0];

    if (!device.hardware_hash) {
      return { bound: false, reason: 'Hardware binding not set' };
    }

    return {
      bound: true,
      boundAt: device.hardware_bound_at
    };
  }

  encryptForStorage(data) {
    const algorithm = 'aes-256-gcm';
    const key = this.getStorageKey();
    const iv = crypto.randomBytes(16);

    const cipher = crypto.createCipheriv(algorithm, key, iv);
    let encrypted = cipher.update(data, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    const authTag = cipher.getAuthTag();

    return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
  }

  decryptFromStorage(encryptedData) {
    if (!encryptedData || !encryptedData.includes(':')) {
      return encryptedData;
    }

    try {
      const algorithm = 'aes-256-gcm';
      const key = this.getStorageKey();
      const parts = encryptedData.split(':');

      if (parts.length !== 3) {
        return encryptedData;
      }

      const iv = Buffer.from(parts[0], 'hex');
      const authTag = Buffer.from(parts[1], 'hex');
      const encrypted = parts[2];

      const decipher = crypto.createDecipheriv(algorithm, key, iv);
      decipher.setAuthTag(authTag);

      let decrypted = decipher.update(encrypted, 'hex', 'utf8');
      decrypted += decipher.final('utf8');

      return decrypted;
    } catch (error) {
      logger.error('Decryption failed:', error.message);
      return encryptedData;
    }
  }

  getStorageKey() {
    const keyMaterial = process.env.HARDWARE_BINDING_KEY;
    const salt = process.env.HARDWARE_BINDING_SALT;
    
    if (!keyMaterial || !salt) {
      throw new Error('HARDWARE_BINDING_KEY and HARDWARE_BINDING_SALT must be set');
    }
    
    return crypto.pbkdf2Sync(keyMaterial, salt, 10000, 32, 'sha256');
  }

  async updateHardwareBinding(deviceId, imei, serialNumber, socId) {
    const existingBinding = await this.checkHardwareBindingExists(deviceId);

    if (existingBinding.bound) {
      logger.info(`Updating existing hardware binding for device: ${deviceId}`);
    }

    return this.storeHardwareBinding(deviceId, imei, serialNumber, socId);
  }

  async removeHardwareBinding(deviceId) {
    await db.query(
      `UPDATE devices
       SET hardware_hash = NULL,
           hardware_salt = NULL,
           hardware_imei_encrypted = NULL,
           hardware_serial_encrypted = NULL,
           hardware_soc_encrypted = NULL,
           hardware_bound_at = NULL,
           updated_at = NOW()
       WHERE id = $1`,
      [deviceId]
    );

    logger.info(`Hardware binding removed for device: ${deviceId}`);
  }

  generateEnrollmentHardwareChallenge(deviceId) {
    const challenge = crypto.randomBytes(32).toString('hex');
    const expiresAt = Date.now() + (15 * 60 * 1000);

    return {
      challenge,
      deviceId,
      expiresAt,
      expiresAtISO: new Date(expiresAt).toISOString()
    };
  }

  verifyEnrollmentChallenge(storedChallenge, receivedChallenge, expiresAt) {
    if (Date.now() > expiresAt) {
      throw new Error('Hardware challenge has expired');
    }

    return this.safeCompare(storedChallenge, receivedChallenge);
  }

  async logSecurityEvent(eventType, metadata) {
    try {
      await db.query(
        `INSERT INTO security_events (event_type, severity, device_id, metadata, created_at)
         VALUES ($1, $2, $3, $4, NOW())`,
        [eventType, 'warning', metadata.deviceId || null, JSON.stringify(metadata)]
      );
    } catch (error) {
      logger.error('Failed to log security event:', error);
    }
  }
}

module.exports = new HardwareBindingService();
