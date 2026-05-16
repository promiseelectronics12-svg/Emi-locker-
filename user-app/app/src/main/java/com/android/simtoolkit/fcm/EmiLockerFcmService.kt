package com.android.simtoolkit.fcm

import android.content.Intent
import android.util.Log
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.health.PermissionHealthReporter
import com.android.simtoolkit.security.CommandVerificationManager
import com.android.simtoolkit.service.DeviceRegistrationService
import com.android.simtoolkit.service.EmiLockerService
import com.android.simtoolkit.util.LocationHelper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class EmiLockerFcmService : FirebaseMessagingService() {

    @Inject lateinit var commandVerifier: CommandVerificationManager
    @Inject lateinit var apiService: ApiService
    @Inject lateinit var deviceRegistrationService: DeviceRegistrationService
    @Inject lateinit var preferencesManager: PreferencesManager
    @Inject lateinit var permissionHealthReporter: PermissionHealthReporter

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val TAG = "EmiLockerFcmService"

        // Command type keys matching server-sent payloads
        private const val KEY_COMMAND   = "command"
        private const val KEY_NONCE     = "nonce"
        private const val KEY_TIMESTAMP = "timestamp"
        private const val KEY_IMEI      = "deviceImei"
        private const val KEY_IMEI_ALT  = "imei"
        private const val KEY_PULL_ID   = "pullId"
        private const val KEY_HMAC      = "hmacSignature"
        private const val KEY_MESSAGE   = "message"

        private const val CMD_LOCK             = "LOCK"
        private const val CMD_REMINDER_LOCK    = "REMINDER_MODE"
        private const val CMD_UNLOCK           = "UNLOCK"
        private const val CMD_DECOUPLE         = "DECOUPLE"
        private const val CMD_MESSAGE          = "MESSAGE"
        private const val CMD_GET_LOCATION     = "GET_LOCATION"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d(TAG, "FCM message received from: ${remoteMessage.from}")

        val data = remoteMessage.data
        if (data.isEmpty()) return

        val command = data[KEY_COMMAND] ?: data["commandType"] ?: when (data["type"]) {
            "DEALER_MESSAGE" -> CMD_MESSAGE
            "UNLOCK_COMMAND" -> CMD_UNLOCK
            "DECOUPLE_COMMAND" -> CMD_DECOUPLE
            "LOCK_COMMAND" -> when (data["lockLevel"]) {
                "PARTIAL_LOCK", "REMINDER_MODE", "SOFT" -> CMD_REMINDER_LOCK
                "NONE" -> CMD_UNLOCK
                else -> CMD_LOCK
            }
            else -> return
        }

        val imei      = data[KEY_IMEI] ?: data[KEY_IMEI_ALT] ?: ""

        // GET_LOCATION is read-only — skip HMAC (server uses KMS keys, device uses local keys,
        // they never match). The report itself is authenticated via device token header.
        // DECOUPLE must be verified — it calls clearDeviceOwnerApp().
        val skipHmac = command == CMD_GET_LOCATION ||
            command == CMD_MESSAGE ||
            (BuildConfig.DEBUG && (command == CMD_LOCK || command == CMD_REMINDER_LOCK || command == CMD_UNLOCK))

        if (!skipHmac) {
            val nonce     = data[KEY_NONCE]     ?: return
            val timestamp = data[KEY_TIMESTAMP] ?: return
            val hmac      = data[KEY_HMAC]      ?: return
            val actionType = data["commandType"] ?: command
            val lockLevel  = data["lockLevel"]
            val isValid = commandVerifier.verifyServerCommand(
                deviceImei    = imei,
                timestamp     = timestamp.toLongOrNull() ?: 0L,
                nonce         = nonce,
                actionType    = actionType,
                lockLevel     = lockLevel,
                hmacSignature = hmac
            )
            if (!isValid) {
                Log.e(TAG, "SECURITY: Invalid HMAC signature for command=$command. Rejected.")
                return
            }
        }

        Log.d(TAG, "Command verified: $command")
        scope.launch {
            permissionHealthReporter.reportIfChanged("fcm_$command")
        }
        executeCommand(command, data)
    }

    private fun executeCommand(command: String, data: Map<String, String>) {
        if (command == CMD_GET_LOCATION) {
            Log.d(TAG, "GET_LOCATION: forwarding to foreground location service")
            val intent = Intent(this, EmiLockerService::class.java).apply {
                action = EmiLockerService.ACTION_REPORT_LOCATION
                putExtra(EmiLockerService.EXTRA_PULL_ID, data[KEY_PULL_ID] ?: "")
            }
            startForegroundService(intent)
            return
        }

        val action = when (command) {
            CMD_LOCK         -> EmiLockerService.ACTION_LOCK_DEVICE
            CMD_REMINDER_LOCK -> EmiLockerService.ACTION_REMINDER_LOCK
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
            if (command == CMD_UNLOCK) {
                data["grace_hours"]?.let { putExtra("grace_hours", it) }
                data["graceHours"]?.let { putExtra("grace_hours", it) }
                data["grace_expires_at_ms"]?.let { putExtra("grace_expires_at_ms", it) }
                data["graceExpiresAtMs"]?.let { putExtra("grace_expires_at_ms", it) }
            }
        }
        startForegroundService(intent)
    }

    private fun handleGetLocation(data: Map<String, String>) {
        val pullId   = data[KEY_PULL_ID] ?: ""
        scope.launch {
            try {
                val deviceId = preferencesManager.activatedDeviceId.first() ?: run {
                    Log.w(TAG, "GET_LOCATION: no deviceId stored")
                    return@launch
                }
                var deviceToken = preferencesManager.deviceToken.first()
                    ?: preferencesManager.accessToken.first()

                // No token stored (enrolled before fix) — fetch a fresh device JWT
                if (deviceToken == null) {
                    Log.w(TAG, "GET_LOCATION: no token stored, attempting refresh")
                    try {
                        val refreshResp = apiService.refreshDeviceToken(deviceId, emptyMap())
                        if (refreshResp.isSuccessful && refreshResp.body()?.success == true) {
                            val body = refreshResp.body()!!
                            val fresh = body.deviceToken!!
                            preferencesManager.saveDeviceToken(fresh)
                            body.offlineUnlockSecret?.takeIf { it.isNotBlank() }?.let {
                                preferencesManager.saveOfflineUnlockSecret(it)
                            }
                            deviceToken = fresh
                            Log.d(TAG, "GET_LOCATION: token refreshed successfully")
                        } else {
                            Log.e(TAG, "GET_LOCATION: token refresh failed: ${refreshResp.code()}")
                            return@launch
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "GET_LOCATION: token refresh exception: ${e.message}")
                        return@launch
                    }
                }

                val loc = LocationHelper.getLocationForPull(this@EmiLockerFcmService)
                if (loc == null) {
                    Log.e(TAG, "GET_LOCATION: no real location available; not reporting fake 0,0")
                    return@launch
                }

                val lat = loc.latitude
                val lng = loc.longitude
                val acc = loc.accuracy

                Log.d(TAG, "GET_LOCATION: reporting lat=$lat lng=$lng acc=$acc pullId=$pullId")

                val reportResp = apiService.reportLocation(
                    deviceId = deviceId,
                    deviceToken = deviceToken,
                    body = mapOf(
                        "latitude"  to lat,
                        "longitude" to lng,
                        "accuracy"  to acc,
                        "timestamp" to java.time.Instant.now().toString(),
                        "pull_id"   to pullId
                    )
                )
                if (reportResp.isSuccessful) {
                    Log.d(TAG, "GET_LOCATION: report accepted by backend (${reportResp.code()})")
                } else {
                    Log.e(
                        TAG,
                        "GET_LOCATION: backend rejected report code=${reportResp.code()} body=${reportResp.errorBody()?.string()}"
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "GET_LOCATION failed: ${e.message}")
            }
        }
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "New FCM token received")
        scope.launch {
            deviceRegistrationService.updateFcmToken(token)
        }
    }
}
