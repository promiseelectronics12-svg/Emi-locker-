const REQUIRED_VARS = [
  'POSTGRES_URL',
  'REDIS_URL',
  'JWT_SECRET',
  'HMAC_SECRET',
  'FIREBASE_PROJECT_ID',
  'AMAPI_PROJECT',
  'PORT',
  'NODE_ENV',
  'CORS_ORIGIN'
];

function validateEnvironment() {
  const missingVars = [];

  for (const varName of REQUIRED_VARS) {
    if (!process.env[varName]) {
      missingVars.push(varName);
    }
  }

  if (missingVars.length > 0) {
    console.error('FATAL: Missing required environment variables:');
    missingVars.forEach(v => console.error(`  - ${v}`));
    console.error('\nApplication cannot start without these variables.');
    process.exit(1);
  }

  if (process.env.NODE_ENV !== 'production') {
    console.log('Environment validation passed.');
  }
}

module.exports = { validateEnvironment };
