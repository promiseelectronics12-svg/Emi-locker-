package com.android.simtoolkit.service

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.data.remote.api.DevicePreRegisterRequest
import com.google.firebase.messaging.FirebaseMessaging
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DeviceRegistrationService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val apiService: ApiService,
    private val preferencesManager: PreferencesManager
) {
    private val TAG = "DeviceRegistration"

    private fun getAndroidId(): String? =
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)

    private fun getDeviceBoundId(androidId: String?): String =
        androidId?.let { "ANDROID_ID:$it" } ?: "ANDROID_ID:UNKNOWN"

    // Called once at app startup. Modern Android blocks normal apps from reading
    // IMEI, so Android ID is sent as its own field instead of being placed in
    // the IMEI field.
    suspend fun preRegisterIfNeeded() = withContext(Dispatchers.IO) {
        try {
            val alreadyRegistered = preferencesManager.isDevicePreRegistered.firstOrNull() ?: false
            if (alreadyRegistered) return@withContext

            val fcmToken = FirebaseMessaging.getInstance().token.await()
            val androidId = getAndroidId()

            apiService.preRegisterDevice(
                DevicePreRegisterRequest(
                    imei       = null,
                    fcm_token  = fcmToken,
                    brand      = Build.BRAND,
                    model      = Build.MODEL,
                    android_id = androidId,
                    device_bound_id = getDeviceBoundId(androidId)
                )
            )

            preferencesManager.markDevicePreRegistered()
            Log.d(TAG, "Device pre-registered successfully")
        } catch (e: Exception) {
            // Silent failure — will retry next launch until it succeeds
            Log.w(TAG, "Pre-registration failed (will retry)", e)
        }
    }

    // Called after binding completes — ensures enrolled device record has FCM token.
    suspend fun registerFcmForDevice(deviceId: String) = withContext(Dispatchers.IO) {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            val response = apiService.registerDeviceFcmToken(deviceId, mapOf("fcm_token" to token))
            if (response.isSuccessful) {
                Log.d(TAG, "FCM token registered for device $deviceId")
            } else {
                Log.w(TAG, "FCM token registration rejected: ${response.code()}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "FCM token registration failed", e)
        }
    }

    // Re-registers if FCM token rotates (called from EmiLockerFcmService.onNewToken)
    suspend fun updateFcmToken(newToken: String) = withContext(Dispatchers.IO) {
        try {
            val androidId = getAndroidId()
            apiService.preRegisterDevice(
                DevicePreRegisterRequest(
                    imei       = null,
                    fcm_token  = newToken,
                    brand      = Build.BRAND,
                    model      = Build.MODEL,
                    android_id = androidId,
                    device_bound_id = getDeviceBoundId(androidId)
                )
            )
            Log.d(TAG, "FCM token updated on server")
        } catch (e: Exception) {
            Log.w(TAG, "FCM token update failed", e)
        }
    }
}
