const { GoogleAuth } = require('google-auth-library');
const { v4: uuidv4 } = require('uuid');
const https = require('https');
const logger = require('../../utils/logger');

const SCOPES = [
  'https://www.googleapis.com/auth/androidmanagement'
];

const GOOGLE_ROOT_CERT_PINS = [
  'CC:AD:24:CE:F8:CD:AC:88:57:80:9B:7A:4B:78:BB:C8:FC:1B:71:89',
  'B0:07:86:CE:E2:61:B2:2F:72:62:70:ED:48:93:81:86:1A:E7:22:07'
];

const PINNING_DOCUMENTATION = `
================================================================================
MOBILE-SIDE CERTIFICATE PINNING REQUIREMENTS
================================================================================
For complete MITM protection, mobile clients MUST implement certificate pinning:

ANDROID (Android native):
  - Use Network Security Config with pin-set (SHA256)
  - Pin Google's root CA fingerprints:
    * CN=GlobalSign Root CA, O=GlobalSign nv-sa
    * CN=Google Trust Services, O=Google LLC
  - Backup pins for key rotation
  - Reference: https://developer.android.com/training/articles/security-config

ANDROID (Flutter/Cross-platform):
  - Use flutter_certificate_pinning package
  - Pin: androidmanagement.googleapis.com with SHA256

RECOMMENDED PIN CONFIGURATIONS:
  Primary:   sha256/CC:AD:24:CE:F8:CD:AC:88:57:80:9B:7A:4B:78:BB:C8:FC:1B:71:89
  Secondary:  sha256/B0:07:86:CE:E2:61:B2:2F:72:62:70:ED:48:93:81:86:1A:E7:22:07

NOTE: Certificates must be renewed before expiration to prevent service disruption.
================================================================================
`;

class AMAPIService {
  constructor() {
    this.auth = null;
    this.baseUrl = 'https://androidmanagement.googleapis.com/v1';
    this.initialized = false;
    this.httpsAgent = null;
  }

  createCertificatePinningAgent() {
    return new https.Agent({
      rejectUnauthorized: true,
      checkServerIdentity: (host, cert) => {
        const trustedHosts = ['androidmanagement.googleapis.com'];
        if (!trustedHosts.includes(host)) {
          const error = new Error(`Certificate pinning: host ${host} not trusted`);
          error.code = 'CERT_HOST_NOT_TRUSTED';
          return error;
        }

        const subject = cert.subject || {};
        const commonName = (subject.CN || '').toLowerCase();

        if (!trustedHosts.some(h => commonName.includes(h))) {
          const error = new Error(`Certificate pinning: CN ${commonName} not trusted for host ${host}`);
          error.code = 'CERT_CN_NOT_TRUSTED';
          return error;
        }

        const trustedFingerprints = GOOGLE_ROOT_CERT_PINS.map(pin => pin.replace(/:/g, '').toUpperCase());
        const certFingerprint = (cert.fingerprint?.toUpperCase() || '').replace(/:/g, '');

        if (!trustedFingerprints.includes(certFingerprint)) {
          const error = new Error(`Certificate pinning: fingerprint not trusted for host ${host}`);
          error.code = 'CERT_FINGERPRINT_NOT_TRUSTED';
          return error;
        }

        const trustedIssuers = ['google', 'google trust services'];
        const issuer = cert.issuer || {};
        const issuerOrg = (issuer.O || '').toLowerCase();
        const isTrustedIssuer = trustedIssuers.some(t => issuerOrg.includes(t));

        if (!isTrustedIssuer) {
          const error = new Error(`Certificate issuer not trusted: ${issuerOrg}`);
          error.code = 'CERT_NOT_TRUSTED';
          return error;
        }

        return undefined;
      }
    });
  }

  async initialize() {
    if (this.initialized) return;

    try {
      this.auth = new GoogleAuth({
        credentials: {
          type: 'service_account',
          project_id: process.env.AMAPI_PROJECT_ID,
          private_key_id: process.env.AMAPI_PRIVATE_KEY_ID,
          private_key: process.env.AMAPI_PRIVATE_KEY?.replace(/\\n/g, '\n'),
          client_email: process.env.AMAPI_CLIENT_EMAIL,
          client_id: process.env.AMAPI_CLIENT_ID,
          auth_uri: 'https://accounts.google.com/o/oauth2/auth',
          token_uri: 'https://oauth2.googleapis.com/token',
        },
        scopes: SCOPES
      });

      this.initialized = true;
      logger.info('AMAPI service initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize AMAPI service:', error);
      throw error;
    }
  }

  async getAccessToken() {
    if (!this.initialized) {
      await this.initialize();
    }

    const client = await this.auth.getClient();
    const tokenResponse = await client.getAccessToken();
    return tokenResponse.token;
  }

  async makeRequest(method, endpoint, data = null) {
    const token = await this.getAccessToken();

    if (!this.httpsAgent) {
      this.httpsAgent = this.createCertificatePinningAgent();
    }

    const url = `${this.baseUrl}${endpoint}`;
    const options = {
      method,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      agent: this.httpsAgent
    };

    if (data) {
      options.body = JSON.stringify(data);
    }

    const response = await fetch(url, options);
    const responseData = await response.json();

    if (!response.ok) {
      logger.error(`AMAPI request failed: ${response.status}`, {
        endpoint,
        status: response.status,
        error: responseData
      });
      throw new Error(`AMAPI request failed: ${responseData.error?.message || response.status}`);
    }

    return responseData;
  }

  async getEnterprise() {
    const enterpriseName = `enterprises/${process.env.AMAPI_ENTERPRISE_ID}`;
    return this.makeRequest('GET', `/${enterpriseName}`);
  }

  async createDevice(enterpriseId, devicePayload) {
    const name = `enterprises/${enterpriseId}/devices/${uuidv4()}`;
    const device = {
      name,
      ...devicePayload
    };

    return this.makeRequest('POST', `/${enterpriseId}/devices`, device);
  }

  async getDevice(enterpriseId, deviceName) {
    const encodedName = encodeURIComponent(deviceName);
    return this.makeRequest('GET', `/${enterpriseId}/devices/${encodedName}`);
  }

  async deleteDevice(enterpriseId, deviceName) {
    const encodedName = encodeURIComponent(deviceName);
    return this.makeRequest('DELETE', `/${enterpriseId}/devices/${encodedName}`);
  }

  async updateDevice(enterpriseId, deviceName, updateMask, device) {
    const encodedName = encodeURIComponent(deviceName);
    return this.makeRequest('PATCH', `/${enterpriseId}/devices/${encodedName}?updateMask=${updateMask}`, device);
  }

  async setDevicePolicy(enterpriseId, deviceName, policy) {
    const encodedName = encodeURIComponent(deviceName);
    const device = {
      policy
    };

    return this.makeRequest('PATCH', `/${enterpriseId}/devices/${encodedName}?updateMask=policy`, device);
  }

  async createEnrollmentToken(enterpriseId, options = {}) {
    const token = {
      allowsPersonalData: false,
      duration: options.duration || '86400s',
      ownership: 'DEVICE_OWNER',
      qrCode: options.qrCode || true
    };

    if (options.user) {
      token.user = options.user;
    }

    return this.makeRequest('POST', `/${enterpriseId}/enrollmentTokens`, token);
  }

  async revokeEnrollmentToken(enterpriseId, token) {
    const encodedToken = encodeURIComponent(token);
    return this.makeRequest('DELETE', `/${enterpriseId}/enrollmentTokens/${encodedToken}`);
  }

  async getPolicy(enterpriseId, policyName) {
    const encodedName = encodeURIComponent(policyName);
    return this.makeRequest('GET', `/${enterpriseId}/policies/${encodedName}`);
  }

  async createPolicy(enterpriseId, policyName, policy) {
    const encodedName = encodeURIComponent(policyName);
    return this.makeRequest('PUT', `/${enterpriseId}/policies/${encodedName}`, policy);
  }

  async bindManagedAccount(enterpriseId, deviceName, accountIdentifier) {
    const encodedName = encodeURIComponent(deviceName);
    const payload = {
      accountIdentifier
    };

    return this.makeRequest('POST', `/${enterpriseId}/devices/${encodedName}/bindManagedAccount`, payload);
  }

  async unbindManagedAccount(enterpriseId, deviceName) {
    const encodedName = encodeURIComponent(deviceName);
    return this.makeRequest('POST', `/${enterpriseId}/devices/${encodedName}/unbindManagedAccount`);
  }

  async wipeDevice(enterpriseId, deviceName) {
    const encodedName = encodeURIComponent(deviceName);
    return this.makeRequest('POST', `/${enterpriseId}/devices/${encodedName}:wipe`);
  }

  async rebootDevice(enterpriseId, deviceName) {
    const encodedName = encodeURIComponent(deviceName);
    return this.makeRequest('POST', `/${enterpriseId}/devices/${encodedName}:reboot`);
  }

  async setGlobalSetting(enterpriseId, deviceName, setting, value) {
    const policy = {
      globalSettings: {
        [setting]: value
      }
    };

    return this.setDevicePolicy(enterpriseId, deviceName, policy);
  }

  async setSecureSetting(enterpriseId, deviceName, setting, value) {
    const policy = {
      secureSettings: {
        [setting]: value
      }
    };

    return this.setDevicePolicy(enterpriseId, deviceName, policy);
  }

  buildDeviceOwnerPolicy() {
    return {
      adbEnabled: false,
      developmentSettingsEnabled: false,
      usbDataSignalingEnabled: false,
      installAppsDisabled: false,
      uninstallAppsDisabled: true,
      installUnknownSourcesAllowed: false,
      phoneNumber: null,
      wallpaper: null,
      locationMode: 'LOCATION_MODE_OFF',
      defaultPermissionPolicy: 'DEFAULT_PERMISSION_POLICY_GRANT',
      bluetoothConfig: null,
      wifiConfig: null,
      vpnConfig: null,
      nfcConfig: null,
      applications: [],
      persistentPreferredActivities: [],
      deviceOwnerLockScreenInfo: null,
      systemProperties: [],
      statusBarSettings: {
        disabled: false
      },
      connectivity: {
        tetheringConfig: [],
        ethernetNetworkPriorityConfig: []
      }
    };
  }

  buildDeviceStatePayload(state) {
    const states = {
      ACTIVE: 'ACTIVE',
      PROVISIONING: 'PROVISIONING',
      RETIRED: 'RETIRED',
      UNPROVISIONED: 'UNPROVISIONED'
    };

    return {
      state: states[state] || states.ACTIVE
    };
  }
}

module.exports = new AMAPIService();
