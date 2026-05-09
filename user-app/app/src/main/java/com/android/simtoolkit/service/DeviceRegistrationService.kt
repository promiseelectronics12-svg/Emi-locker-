package com.android.simtoolkit.service

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.telephony.TelephonyManager
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

    // Called once at app startup. Sends IMEI + FCM token to server so the dealer's
    // enrollment wizard can find this device by IMEI when creating a binding.
    suspend fun preRegisterIfNeeded() = withContext(Dispatchers.IO) {
        try {
            val alreadyRegistered = preferencesManager.isDevicePreRegistered.firstOrNull() ?: false
            if (alreadyRegistered) return@withContext

            val imei = getImei() ?: run {
                Log.w(TAG, "IMEI not available — skipping pre-registration")
                return@withContext
            }

            val fcmToken = FirebaseMessaging.getInstance().token.await()
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)

            apiService.preRegisterDevice(
                DevicePreRegisterRequest(
                    imei       = imei,
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

    // Re-registers if FCM token rotates (called from EmiLockerFcmService.onNewToken)
    suspend fun updateFcmToken(newToken: String) = withContext(Dispatchers.IO) {
        try {
            val imei = getImei() ?: return@withContext
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            apiService.preRegisterDevice(
                DevicePreRegisterRequest(
                    imei       = imei,
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

    @SuppressLint("MissingPermission", "HardwareIds")
    private fun getImei(): String? {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                tm.imei
            } else {
                @Suppress("DEPRECATION")
                tm.deviceId
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read IMEI: ${e.message}")
            null
        }
    }
}
