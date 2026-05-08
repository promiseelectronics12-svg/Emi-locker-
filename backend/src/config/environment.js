const { apiBaseUrl, firebaseProjectId, firebasePrivateKey, firebaseClientEmail,
  twilioAccountSid, twilioAuthToken, twilioPhoneNumber, redisUrl, databaseUrl,
  hmacSecret, hsmKey, serverId, isProduction, isDevelopment, isLocalhost } = process.env;

const Environment = {
  apiBaseUrl: process.env.API_BASE_URL || 'http://localhost:3000',
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID,
  firebasePrivateKey: process.env.FIREBASE_PRIVATE_KEY,
  firebaseClientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  twilioAccountSid: process.env.TWILIO_ACCOUNT_SID,
  twilioAuthToken: process.env.TWILIO_AUTH_TOKEN,
  twilioPhoneNumber: process.env.TWILIO_PHONE_NUMBER,
  redisUrl: process.env.UPSTASH_REDIS_URL || process.env.REDIS_URL || 'redis://localhost:6379',
  databaseUrl: process.env.DATABASE_URL,
  hmacSecret: process.env.HMAC_SECRET,
  hsmKey: process.env.HSM_KEY,
  serverId: process.env.SERVER_ID || 'server-001',
  isProduction: process.env.NODE_ENV === 'production',
  isDevelopment: process.env.NODE_ENV === 'development',
  isLocalhost: (process.env.API_BASE_URL || '').includes('localhost'),
};

module.exports = { Environment };