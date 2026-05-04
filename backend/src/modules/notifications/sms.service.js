const twilio = require('twilio');

let client = null;

function getClient() {
  if (!client) {
    client = twilio(
      process.env.TWILIO_ACCOUNT_SID,
      process.env.TWILIO_AUTH_TOKEN
    );
  }
  return client;
}

async function sendSMS(to, body) {
  try {
    const message = await getClient().messages.create({
      body,
      to,
      from: process.env.TWILIO_PHONE_NUMBER,
    });

    return {
      success: true,
      messageId: message.sid,
    };
  } catch (error) {
    console.error('Twilio SMS error:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown SMS error',
    };
  }
}

async function sendLockConfirmationSMS(
  devicePhone,
  deviceId,
  lockType
) {
  const message = `EMI Locker: Your device has been ${lockType.toLowerCase().replace('_', ' ')}ed due to payment overdue. Please contact your dealer for assistance. Device: ${deviceId}`;

  return sendSMS(devicePhone, message);
}

async function sendUnlockConfirmationSMS(
  devicePhone,
  deviceId
) {
  const message = `EMI Locker: Your device has been unlocked. Please ensure your next payment is made on time. Device: ${deviceId}`;

  return sendSMS(devicePhone, message);
}

async function sendCriticalAlertSMS(
  devicePhone,
  alertMessage
) {
  return sendSMS(devicePhone, `EMI Locker CRITICAL: ${alertMessage}`);
}

module.exports = {
  sendSMS,
  sendLockConfirmationSMS,
  sendUnlockConfirmationSMS,
  sendCriticalAlertSMS,
};