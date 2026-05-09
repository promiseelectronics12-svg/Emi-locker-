/**
 * One-time script: authorizes the service account to manage the AMAPI enterprise.
 * Run: node scripts/authorize_sa_for_enterprise.js
 */

require('dotenv').config();
const http = require('http');
const { execSync } = require('child_process');
const { OAuth2Client } = require('google-auth-library');

const CALLBACK_PORT = 9876;
const OAUTH_CALLBACK_URL = `http://localhost:${CALLBACK_PORT}/callback`;
const OAUTH_CLIENT_ID = process.env.AMAPI_OAUTH_CLIENT_ID;
const OAUTH_CLIENT_SECRET = process.env.AMAPI_OAUTH_CLIENT_SECRET;
const ENTERPRISE_ID = process.env.AMAPI_ENTERPRISE_ID;
const SERVICE_ACCOUNT_EMAIL = process.env.AMAPI_CLIENT_EMAIL;
const SCOPES = ['https://www.googleapis.com/auth/androidmanagement'];

function openBrowser(url) {
  try { execSync(`start "" "${url}"`, { stdio: 'inherit' }); } catch (e) {
    console.warn('Browser open failed:', e.message);
  }
}

async function getUserToken() {
  return new Promise((resolve, reject) => {
    const oauth2Client = new OAuth2Client(OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, OAUTH_CALLBACK_URL);
    const authUrl = oauth2Client.generateAuthUrl({ access_type: 'offline', scope: SCOPES, prompt: 'consent' });

    const server = http.createServer(async (req, res) => {
      if (!req.url.startsWith('/callback')) { res.writeHead(404); res.end(); return; }
      const code = new URL(req.url, `http://localhost:${CALLBACK_PORT}`).searchParams.get('code');
      if (!code) { res.writeHead(400); res.end('Missing code'); return; }
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end('<h2 style="font-family:sans-serif;text-align:center;margin-top:100px">✅ Authenticated! Return to terminal.</h2>');
      server.close();
      try {
        const { tokens } = await oauth2Client.getToken(code);
        resolve(tokens.access_token);
      } catch (e) { reject(e); }
    });

    server.listen(CALLBACK_PORT, () => console.log(`Listening on port ${CALLBACK_PORT}...`));
    server.on('error', e => reject(new Error(`Port ${CALLBACK_PORT} in use: ${e.message}`)));
    setTimeout(() => { server.close(); reject(new Error('Timeout')); }, 300000);

    console.log('\nOpening browser — sign in with: support@lunaveil.store\n');
    console.log('If browser does not open, paste manually:');
    console.log(authUrl + '\n');
    openBrowser(authUrl);
  });
}

async function main() {
  console.log('\n=== Authorize Service Account for AMAPI Enterprise ===\n');
  console.log('Enterprise:', ENTERPRISE_ID);
  console.log('Service account to authorize:', SERVICE_ACCOUNT_EMAIL);
  console.log('');

  const token = await getUserToken();
  console.log('✓ User authenticated\n');

  console.log('Patching enterprise to authorize service account...');
  const res = await fetch(
    `https://androidmanagement.googleapis.com/v1/enterprises/${ENTERPRISE_ID}?updateMask=contactInfo`,
    {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contactInfo: {
          contactEmail: SERVICE_ACCOUNT_EMAIL,
          dataProtectionOfficerEmail: SERVICE_ACCOUNT_EMAIL,
          euRepresentativeEmail: SERVICE_ACCOUNT_EMAIL,
        }
      })
    }
  );

  const data = await res.json();
  if (!res.ok) {
    console.error('✗ Patch failed:', JSON.stringify(data.error, null, 2));
    process.exit(1);
  }

  console.log('✓ Enterprise patched\n');
  console.log('Testing service account access...');

  const { GoogleAuth } = require('google-auth-library');
  const auth = new GoogleAuth({
    credentials: {
      type: 'service_account',
      project_id: process.env.AMAPI_PROJECT_ID,
      private_key_id: process.env.AMAPI_PRIVATE_KEY_ID,
      private_key: process.env.AMAPI_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      client_email: process.env.AMAPI_CLIENT_EMAIL,
      client_id: process.env.AMAPI_CLIENT_ID,
    },
    scopes: SCOPES
  });
  const client = await auth.getClient();
  const { token: saToken } = await client.getAccessToken();

  const testRes = await fetch(`https://androidmanagement.googleapis.com/v1/enterprises/${ENTERPRISE_ID}`, {
    headers: { Authorization: `Bearer ${saToken}` }
  });
  const testData = await testRes.json();

  if (!testRes.ok) {
    console.error('✗ Service account still cannot access enterprise:', testData.error?.message);
    console.log('\nManual fix needed — see instructions above.');
    process.exit(1);
  }

  console.log('✓ Service account can now manage enterprise:', testData.name);
  console.log('\nAMAPI is fully operational.');
}

main().catch(e => { console.error('\n✗ ERROR:', e.message); process.exit(1); });
