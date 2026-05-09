'use strict';

const { Resend } = require('resend');

let _resend = null;
function getResend() {
  if (!_resend) _resend = new Resend(process.env.RESEND_API_KEY);
  return _resend;
}

const FROM = () => process.env.RESEND_FROM_EMAIL || 'noreply@emi-locker.com';

async function sendDeviceOtp(toEmail, otpCode) {
  await getResend().emails.send({
    from: FROM(),
    to: toEmail,
    subject: 'New Device Login — Verification Code',
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:auto">
        <h2 style="color:#0D1117">New Device Detected</h2>
        <p>A login attempt was made from a new device on your EMI Locker account.</p>
        <p style="font-size:36px;font-weight:900;letter-spacing:8px;color:#00A86B;margin:24px 0">
          ${otpCode}
        </p>
        <p>Enter this code in the app. It expires in <strong>10 minutes</strong>.</p>
        <p style="color:#6B7280;font-size:13px">
          If you did not attempt to log in, please change your password immediately.
        </p>
      </div>
    `,
  });
}

async function sendResellerInvite(toEmail, name, inviteUrl) {
  await getResend().emails.send({
    from: FROM(),
    to: toEmail,
    subject: 'You\'ve been invited to join EMI Locker as a Reseller',
    html: `
      <div style="font-family:sans-serif;max-width:520px;margin:auto">
        <h2 style="color:#0D1117">Welcome, ${name}!</h2>
        <p>You have been invited by the EMI Locker platform admin to join as a reseller partner.</p>
        <p>Click the button below to set up your account:</p>
        <a href="${inviteUrl}"
           style="display:inline-block;padding:12px 24px;background:#00A86B;color:#fff;border-radius:8px;text-decoration:none;font-weight:600;margin:16px 0">
          Set Up My Account
        </a>
        <p style="color:#6B7280;font-size:13px">This invite link expires in 48 hours.</p>
      </div>
    `,
  });
}

module.exports = { sendDeviceOtp, sendResellerInvite };
