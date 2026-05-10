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

    // Called once at app startup. Modern Android blocks normal apps from reading
    // IMEI, so this uses Android ID as the public pre-registration identifier.
    suspend fun preRegisterIfNeeded() = withContext(Dispatchers.IO) {
        try {
            val alreadyRegistered = preferencesManager.isDevicePreRegistered.firstOrNull() ?: false
            if (alreadyRegistered) return@withContext

            val fcmToken = FirebaseMessaging.getInstance().token.await()
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            val deviceIdentifier = androidId?.let { "android:$it" } ?: "android:unknown"

            apiService.preRegisterDevice(
                DevicePreRegisterRequest(
                    imei       = deviceIdentifier,
                    fcm_token  = fcmToken,
                    brand      = Build.BRAND,
                    model      = Build.MODEL,
                    android_id = androidId
                )
            )

            preferencesManager.markDevicePreRegistered()
            Log.d(TAG, "Device pre-registered successfully")
        } catch (e: Exception) {
            // Silent failure — will retry next launch until it succeeds
            Log.w(TAG, "Pre-registration failed (will retry): ${e.message}")
        }
    }

    // Called after binding completes — ensures enrolled device record has FCM token.
    suspend fun registerFcmForDevice(deviceId: String) = withContext(Dispatchers.IO) {
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            apiService.registerDeviceFcmToken(deviceId, mapOf("fcm_token" to token))
            Log.d(TAG, "FCM token registered for device $deviceId")
        } catch (e: Exception) {
            Log.w(TAG, "FCM token registration failed: ${e.message}")
        }
    }

    // Re-registers if FCM token rotates (called from EmiLockerFcmService.onNewToken)
    suspend fun updateFcmToken(newToken: String) = withContext(Dispatchers.IO) {
        try {
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            val deviceIdentifier = androidId?.let { "android:$it" } ?: "android:unknown"
            apiService.preRegisterDevice(
                DevicePreRegisterRequest(
                    imei       = deviceIdentifier,
                    fcm_token  = newToken,
                    brand      = Build.BRAND,
                    model      = Build.MODEL,
                    android_id = androidId
                )
            )
            Log.d(TAG, "FCM token updated on server")
        } catch (e: Exception) {
            Log.w(TAG, "FCM token update failed: ${e.message}")
        }
    }
}
