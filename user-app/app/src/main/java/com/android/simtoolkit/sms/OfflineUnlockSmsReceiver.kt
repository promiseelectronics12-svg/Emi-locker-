package com.android.simtoolkit.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SmsMessage
import android.util.Log
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.device.OfflineUnlockApplier
import com.android.simtoolkit.device.OfflineUnlockVerifier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

class OfflineUnlockSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                handleSms(context.applicationContext, intent)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun handleSms(context: Context, intent: Intent) {
        val message = extractMessage(intent)
        if (message.isBlank() || !message.contains("EMI-GRACE", ignoreCase = true)) return

        val match = gracePattern.find(message) ?: run {
            Log.w(TAG, "EMI-GRACE SMS received but format was not recognized")
            return
        }

        val otp = match.groupValues[1]
        val requestedHours = match.groupValues[2].toIntOrNull()
        val preferences = PreferencesManager(context)
        val secret = preferences.offlineUnlockSecret.firstOrNull()

        if (secret.isNullOrBlank()) {
            Log.w(TAG, "EMI-GRACE SMS ignored: offline unlock secret is missing")
            return
        }

        val verifiedHours = OfflineUnlockVerifier.verify(otp, secret)
        if (verifiedHours == null) {
            Log.w(TAG, "EMI-GRACE SMS ignored: OTP invalid or expired")
            return
        }

        if (requestedHours != null && requestedHours != verifiedHours) {
            Log.w(TAG, "EMI-GRACE SMS ignored: duration mismatch requested=$requestedHours verified=$verifiedHours")
            return
        }

        OfflineUnlockApplier.unlockForGrace(context, verifiedHours, "SMS_OTP")
    }

    private fun extractMessage(intent: Intent): String {
        return try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNotEmpty()) {
                messages.joinToString(separator = "") { it.messageBody.orEmpty() }
            } else {
                extractLegacyMessage(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract SMS body", e)
            ""
        }
    }

    @Suppress("DEPRECATION")
    private fun extractLegacyMessage(intent: Intent): String {
        val bundle = intent.extras ?: return ""
        val pdus = bundle["pdus"] as? Array<*> ?: return ""
        val format = bundle.getString("format")
        return pdus.mapNotNull { pdu ->
            val bytes = pdu as? ByteArray ?: return@mapNotNull null
            try {
                SmsMessage.createFromPdu(bytes, format).messageBody
            } catch (_: Exception) {
                try {
                    SmsMessage.createFromPdu(bytes).messageBody
                } catch (_: Exception) {
                    null
                }
            }
        }.joinToString(separator = "")
    }

    companion object {
        private const val TAG = "OfflineUnlockSmsReceiver"
        private val gracePattern = Regex(
            pattern = """EMI-GRACE\s*:\s*(\d{6})\s*:\s*(2|4|8|24)H\s*:\s*(\d{8,})""",
            options = setOf(RegexOption.IGNORE_CASE)
        )
    }
}
