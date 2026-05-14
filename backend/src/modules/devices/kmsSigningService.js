const crypto = require('crypto');
const {
  KMSClient,
  MessageType,
  SignCommand,
  SigningAlgorithmSpec
} = require('@aws-sdk/client-kms');
const logger = require('../../utils/logger');

class KmsSigningService {
  constructor() {
    this.kmsClient = null;
    this.isInitialized = false;
  }

  async initialize() {
    if (this.isInitialized) return;

    const provider = process.env.KMS_PROVIDER || 'env';

    if (provider === 'gcp') {
      if (
        !process.env.GCP_PROJECT_ID ||
        !process.env.GCP_KMS_KEY_RING ||
        !process.env.GCP_KMS_KEY_NAME
      ) {
        throw new Error('GCP KMS configuration missing');
      }
      this.kmsClient = new GcpKmsClient({
        projectId: process.env.GCP_PROJECT_ID,
        location: process.env.GCP_KMS_LOCATION || 'global',
        keyRing: process.env.GCP_KMS_KEY_RING,
        keyName: process.env.GCP_KMS_KEY_NAME
      });
    } else if (provider === 'aws') {
      if (!process.env.AWS_REGION || !process.env.AWS_KMS_KEY_ID) {
        throw new Error(
          'AWS KMS configuration missing: AWS_REGION and AWS_KMS_KEY_ID are required'
        );
      }
      this.kmsClient = new AwsKmsClient({
        region: process.env.AWS_REGION,
        keyId: process.env.AWS_KMS_KEY_ID,
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
      });
    } else if (provider === 'env') {
      if (!process.env.LOCK_COMMAND_SIGNING_SECRET) {
        throw new Error('LOCK_COMMAND_SIGNING_SECRET is required when provider is "env"');
      }
      this.kmsClient = null;
    } else {
      throw new Error(`Invalid KMS_PROVIDER: ${provider}`);
    }

    this.isInitialized = true;
    logger.info('KMS signing service initialized', { provider });
  }

  async sign(payload) {
    await this.initialize();

    let normalizedPayload = payload;

    if (payload.message !== undefined) {
      normalizedPayload = {
        imei: payload.imei,
        timestamp: payload.timestamp,
        nonce: payload.nonce,
        message: JSON.stringify(payload.message)
      };
    }

    if (!this.kmsClient) {
      return this.signWithEnvVar(normalizedPayload);
    }

    try {
      const payloadHash = crypto
        .createHash('sha256')
        .update(JSON.stringify(normalizedPayload))
        .digest();
      const signature = await this.kmsClient.sign(payloadHash);
      return {
        signature,
        provider: this.kmsClient.provider,
        keyId: this.kmsClient.keyId,
        algorithm: 'RS256'
      };
    } catch (error) {
      logger.error('KMS signing failed', { error: error.message });
      throw error;
    }
  }

  signWithEnvVar(payload) {
    const secretKey = process.env.LOCK_COMMAND_SIGNING_SECRET;
    if (!secretKey) {
      throw new Error('LOCK_COMMAND_SIGNING_SECRET must be set');
    }
    const message = typeof payload === 'string' ? payload : JSON.stringify(payload);
    const hmac = crypto.createHmac('sha256', secretKey);
    hmac.update(message);
    return {
      signature: hmac.digest('hex'),
      provider: 'env',
      keyId: 'env-key',
      algorithm: 'HS256'
    };
  }

  async verifySignature(payload, signature, options = {}) {
    const { provider, keyId } = options;

    try {
      const result = await this.sign(payload);

      const sigBuffer = Buffer.from(signature, 'hex');
      const expectedBuffer = Buffer.from(result.signature, 'hex');
      if (sigBuffer.length !== expectedBuffer.length) {
        return false;
      }
      return crypto.timingSafeEqual(sigBuffer, expectedBuffer);
    } catch (error) {
      logger.error('Signature verification error:', error);
      return false;
    }
  }
}

class GcpKmsClient {
  constructor(options) {
    this.projectId = options.projectId;
    this.location = options.location;
    this.keyRing = options.keyRing;
    this.keyName = options.keyName;
    this.provider = 'gcp';
    this.keyId = `projects/${this.projectId}/locations/${this.location}/keyRings/${this.keyRing}/cryptoKeys/${this.keyName}`;
  }

  async sign(data) {
    const { GoogleAuth } = require('google-auth-library');
    const auth = new GoogleAuth({
      scopes: 'https://www.googleapis.com/auth/cloudkms'
    });

    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();

    const url = `https://cloudkms.googleapis.com/v1/${this.keyId}:sign`;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        digest: {
          sha256: data.toString('base64')
        }
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`GCP KMS sign failed: ${error}`);
    }

    const result = await response.json();
    return result.signature;
  }
}

class AwsKmsClient {
  constructor(options) {
    if (!/^[a-z]{2}-[a-z]+-\d$/.test(options.region)) {
      throw new Error('Invalid AWS region format for KMS');
    }
    this.region = options.region;
    this.keyId = options.keyId;
    this.accessKeyId = options.accessKeyId;
    this.secretAccessKey = options.secretAccessKey;
    this.provider = 'aws';
    this.client = new KMSClient({
      region: this.region,
      credentials:
        this.accessKeyId && this.secretAccessKey
          ? {
              accessKeyId: this.accessKeyId,
              secretAccessKey: this.secretAccessKey
            }
          : undefined
    });
  }

  async sign(data) {
    const command = new SignCommand({
      KeyId: this.keyId,
      Message: data,
      MessageType: MessageType.DIGEST,
      SigningAlgorithm: SigningAlgorithmSpec.RSASSA_PKCS1_V1_5_SHA_256
    });
    const result = await this.client.send(command);
    return Buffer.from(result.Signature).toString('base64');
  }
}

module.exports = new KmsSigningService();
