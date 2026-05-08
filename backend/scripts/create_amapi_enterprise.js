/**
 * One-time script to create AMAPI enterprise using user OAuth flow.
 * Run: node scripts/create_amapi_enterprise.js
 */

require('dotenv').config();
const http = require('http');
const { execSync } = require('child_process');
const { GoogleAuth, OAuth2Client } = require('google-auth-library');

const PROJECT_ID = process.env.AMAPI_PROJECT_ID;
const CALLBACK_PORT = 9876;
const OAUTH_CALLBACK_URL = `http://localhost:${CALLBACK_PORT}/callback`;
// AMAPI requires HTTPS — use our own Vercel-hosted callback page
const AMAPI_CALLBACK_URL = 'https://emi-locker.vercel.app/amapi-callback';

const OAUTH_CLIENT_ID = process.env.AMAPI_OAUTH_CLIENT_ID;
const OAUTH_CLIENT_SECRET = process.env.AMAPI_OAUTH_CLIENT_SECRET;
const SCOPES = ['https://www.googleapis.com/auth/androidmanagement'];

function openBrowser(url) {
  try {
    execSync(`start "" "${url}"`, { stdio: 'inherit' });
  } catch (e) {
    console.warn('   ⚠️  Browser open failed: ' + e.message);
  }
}

// Step 1: Get user OAuth token via browser
function getUserOAuthToken() {
  return new Promise((resolve, reject) => {
    const oauth2Client = new OAuth2Client(OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, OAUTH_CALLBACK_URL);

    const authUrl = oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: SCOPES,
      prompt: 'consent'
    });

    let enterpriseToken = null;

    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, `http://localhost:${CALLBACK_PORT}`);

      if (!req.url.startsWith('/callback')) {
        res.writeHead(404); res.end(); return;
      }

      // This callback might be from Google OAuth OR from AMAPI signup
      const code = url.searchParams.get('code');
      const et = url.searchParams.get('enterpriseToken');

      if (et) {
        // AMAPI signup callback
        enterpriseToken = et;
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end('<h2 style="font-family:sans-serif;text-align:center;margin-top:100px">✅ Done! Return to your terminal.</h2><script>setTimeout(()=>window.close(),2000)</script>');
        server.close();
        resolve({ type: 'enterprise', enterpriseToken });
        return;
      }

      if (code) {
        // OAuth callback
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end('<h2 style="font-family:sans-serif;text-align:center;margin-top:100px">✅ Authenticated! Return to your terminal.</h2><script>setTimeout(()=>window.close(),2000)</script>');
        server.close();

        try {
          const { tokens } = await oauth2Client.getToken(code);
          oauth2Client.setCredentials(tokens);
          resolve({ type: 'oauth', client: oauth2Client, tokens });
        } catch (e) {
          reject(e);
        }
        return;
      }

      res.writeHead(400); res.end('Missing code or enterpriseToken');
    });

    server.listen(CALLBACK_PORT, () => {
      console.log(`   Listening on port ${CALLBACK_PORT}...`);
    });
    server.on('error', (e) => reject(new Error(`Port ${CALLBACK_PORT} in use: ${e.message}`)));
    setTimeout(() => { server.close(); reject(new Error('Timeout: 5 minutes')); }, 300000);

    console.log('\n   Opening browser — sign in with: support@lunaveil.store\n');
    console.log('   If browser does not open, paste this URL manually:');
    console.log('   ' + authUrl + '\n');
    openBrowser(authUrl);
  });
}

async function createSignupUrl(accessToken) {
  const res = await fetch(
    `https://androidmanagement.googleapis.com/v1/signupUrls?projectId=${PROJECT_ID}&callbackUrl=${encodeURIComponent(AMAPI_CALLBACK_URL)}`,
    { method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' } }
  );
  const data = await res.json();
  if (!res.ok) throw new Error(`signupUrls.create failed: ${JSON.stringify(data.error)}`);
  return data;
}

async function getServiceAccountToken() {
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
  const { token } = await client.getAccessToken();
  return token;
}

async function createEnterprise(token, enterpriseToken, signupUrlName) {
  const res = await fetch(
    `https://androidmanagement.googleapis.com/v1/enterprises?projectId=${PROJECT_ID}&enterpriseToken=${enterpriseToken}&signupUrlName=${encodeURIComponent(signupUrlName)}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({})
    }
  );
  const data = await res.json();
  if (!res.ok) throw new Error(`enterprises.create failed: ${JSON.stringify(data.error)}`);
  return data;
}

function waitForEnterpriseToken() {
  const readline = require('readline');
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('   Paste the enterpriseToken from the browser page and press Enter:\n   > ', (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function main() {
  console.log('\n=== AMAPI Enterprise Setup ===\n');

  // Step 1: User OAuth login
  console.log('Step 1: User login (needed to authorize enterprise creation)...');
  const oauthResult = await getUserOAuthToken();
  const userAccessToken = oauthResult.tokens.access_token;
  console.log('   ✓ User authenticated\n');

  // Step 2: Create signup URL using user token
  console.log('Step 2: Creating Android Management signup URL...');
  const { url: signupUrl, name: signupUrlName } = await createSignupUrl(userAccessToken);
  console.log('   ✓ Signup URL ready\n');

  // Step 3: Open signup URL for enterprise enrollment
  console.log('Step 3: Complete Android Management enrollment in browser...');
  console.log('   Browser opening — complete the org setup wizard.');
  console.log('   After finishing, the page shows an enterpriseToken value — copy it.\n');
  console.log('   If browser does not open:');
  console.log('   ' + signupUrl + '\n');
  openBrowser(signupUrl);

  const enterpriseToken = await waitForEnterpriseToken();
  console.log('   ✓ Enterprise token received\n');

  // Step 4: Create enterprise using service account
  console.log('Step 4: Creating enterprise record...');
  const saToken = await getServiceAccountToken();
  const enterprise = await createEnterprise(saToken, enterpriseToken, signupUrlName);

  const enterpriseId = enterprise.name?.replace('enterprises/', '') || enterprise.name;

  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║           ENTERPRISE CREATED ✓               ║');
  console.log('╠══════════════════════════════════════════════╣');
  console.log(`║  AMAPI_ENTERPRISE_ID=${enterpriseId}`);
  console.log('╚══════════════════════════════════════════════╝\n');
  console.log('Paste the enterprise ID above back to Claude.\n');
}

main().catch(e => {
  console.error('\n✗ ERROR:', e.message);
  process.exit(1);
});
