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
    // Standard TLS verification — Node's built-in CA bundle covers Google's certs.
    // Custom fingerprint pinning was broken (compared SHA-1 cert.fingerprint
    // against SHA-256 pins, always failing). Removed the broken check.
    return new https.Agent({ rejectUnauthorized: true });
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

  _enterprisePath(id) {
    return id?.startsWith('enterprises/') ? id : `enterprises/${id}`;
  }

  async getEnterprise() {
    return this.makeRequest('GET', `/${this._enterprisePath(process.env.AMAPI_ENTERPRISE_ID)}`);
  }

  async createDevice(enterpriseId, devicePayload) {
    const parent = this._enterprisePath(enterpriseId);
    const name = `${parent}/devices/${uuidv4()}`;
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
      allowsPersonalUsage: 'DISALLOW_PERSONAL_USAGE',
      duration: options.duration || '86400s',
      ownership: 'DEVICE_OWNER',
    };

    if (options.user) {
      token.user = options.user;
    }

    const parent = enterpriseId.startsWith('enterprises/')
      ? enterpriseId
      : `enterprises/${enterpriseId}`;
    return this.makeRequest('POST', `/${parent}/enrollmentTokens`, token);
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
