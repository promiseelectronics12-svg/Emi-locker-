package com.android.simtoolkit.fcm

import android.content.Intent
import android.util.Log
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.security.CommandVerificationManager
import com.android.simtoolkit.service.EmiLockerService
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class EmiLockerFcmService : FirebaseMessagingService() {

    @Inject lateinit var commandVerifier: CommandVerificationManager
    @Inject lateinit var apiService: ApiService

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val TAG = "EmiLockerFcmService"

        // Command type keys matching server-sent payloads
        private const val KEY_COMMAND   = "command"
        private const val KEY_NONCE     = "nonce"
        private const val KEY_TIMESTAMP = "timestamp"
        private const val KEY_IMEI      = "deviceImei"
        private const val KEY_HMAC      = "hmacSignature"
        private const val KEY_MESSAGE   = "message"

        private const val CMD_LOCK         = "LOCK"
        private const val CMD_PARTIAL_LOCK = "PARTIAL_LOCK"
        private const val CMD_UNLOCK       = "UNLOCK"
        private const val CMD_DECOUPLE     = "DECOUPLE"
        private const val CMD_MESSAGE      = "MESSAGE"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d(TAG, "FCM message received from: ${remoteMessage.from}")

        val data = remoteMessage.data
        if (data.isEmpty()) return

        val command   = data[KEY_COMMAND]   ?: return
        val nonce     = data[KEY_NONCE]     ?: return
        val timestamp = data[KEY_TIMESTAMP] ?: return
        val imei      = data[KEY_IMEI]      ?: return
        val hmac      = data[KEY_HMAC]      ?: return

        // Verify HMAC signature before executing any command
        val isValid = commandVerifier.verifyCommand(
            deviceImei   = imei,
            timestamp    = timestamp.toLongOrNull() ?: 0L,
            nonce        = nonce,
            actionType   = command,
            hmacSignature = hmac
        )

        if (!isValid) {
            Log.e(TAG, "SECURITY: Invalid HMAC signature for command=$command. Rejected.")
            return
        }

        Log.d(TAG, "Command verified: $command")
        executeCommand(command, data)
    }

    private fun executeCommand(command: String, data: Map<String, String>) {
        val action = when (command) {
            CMD_LOCK         -> EmiLockerService.ACTION_LOCK_DEVICE
            CMD_PARTIAL_LOCK -> EmiLockerService.ACTION_PARTIAL_LOCK
            CMD_UNLOCK       -> EmiLockerService.ACTION_UNLOCK
            CMD_DECOUPLE     -> EmiLockerService.ACTION_DECOUPLE
            CMD_MESSAGE      -> EmiLockerService.ACTION_BROADCAST_MESSAGE
            else -> {
                Log.w(TAG, "Unknown command: $command")
                return
            }
        }

        val intent = Intent(this, EmiLockerService::class.java).apply {
            this.action = action
            if (command == CMD_MESSAGE) {
                putExtra(EmiLockerService.EXTRA_MESSAGE, data[KEY_MESSAGE])
            }
        }
        startForegroundService(intent)
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "New FCM token received")
        // Report new token to server so lock commands continue to reach this device
        scope.launch {
            try {
                apiService.updateFcmToken(token)
                Log.d(TAG, "FCM token updated on server")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update FCM token on server", e)
            }
        }
    }
}

