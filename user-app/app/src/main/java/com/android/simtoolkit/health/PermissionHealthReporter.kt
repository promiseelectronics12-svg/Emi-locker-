package com.android.simtoolkit.health

import android.Manifest
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.device.DeviceAdminReceiver
import com.android.simtoolkit.model.LockState
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.firstOrNull
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PermissionHealthReporter @Inject constructor(
    @ApplicationContext private val context: Context,
    private val apiService: ApiService,
    private val preferencesManager: PreferencesManager
) {
    suspend fun reportIfChanged(
        source: String,
        force: Boolean = false,
        lockState: LockState? = null
    ) {
        val deviceId = preferencesManager.activatedDeviceId.firstOrNull()
        val deviceToken = preferencesManager.deviceToken.firstOrNull()
            ?: preferencesManager.accessToken.firstOrNull()

        if (deviceId.isNullOrBlank() || deviceToken.isNullOrBlank()) {
            Log.d(TAG, "Permission health skipped: device is not bound yet")
            return
        }

        val snapshot = currentSnapshot()
        val signature = snapshot.signature()
        val previous = preferencesManager.permissionHealthSignature.firstOrNull()
        val missingDealerContact = preferencesManager.dealerPhone.firstOrNull().isNullOrBlank()

        if (!force && previous == signature && !missingDealerContact) {
            Log.d(TAG, "Permission health unchanged")
            return
        }

        try {
            val response = apiService.sendDeviceHeartbeat(
                deviceToken,
                snapshot.toHeartbeatBody(source, lockState)
            )
            if (response.isSuccessful) {
                response.body()?.let { body ->
                    val dealerName = body.dealerName?.takeIf { it.isNotBlank() }
                    val dealerPhone = body.dealerPhone?.takeIf { it.isNotBlank() }
                    if (dealerName != null || dealerPhone != null) {
                        preferencesManager.saveDealerInfo(dealerName ?: "Dealer", dealerPhone.orEmpty())
                    }
                }
                preferencesManager.savePermissionHealthSignature(signature)
                Log.d(TAG, "Permission health reported: ${snapshot.status}")
            } else {
                Log.w(TAG, "Permission health rejected code=${response.code()}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Permission health report failed: ${e.message}")
        }
    }

    suspend fun reportCurrentLockState(source: String, force: Boolean = true) {
        val currentState = preferencesManager.getCurrentLockState()
        reportIfChanged(source, force = force, lockState = currentState)
    }

    fun currentSnapshot(): PermissionHealthSnapshot {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(context, DeviceAdminReceiver::class.java)
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager

        val fineLocation = hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarseLocation = hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        val backgroundLocation = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            hasPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        val notifications = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            hasPermission(Manifest.permission.POST_NOTIFICATIONS)
        val notificationChannelsEnabled = areNotificationsEnabled()

        return PermissionHealthSnapshot(
            overlay = Settings.canDrawOverlays(context),
            fineLocation = fineLocation,
            coarseLocation = coarseLocation,
            backgroundLocation = backgroundLocation,
            receiveSms = hasPermission(Manifest.permission.RECEIVE_SMS),
            notifications = notifications && notificationChannelsEnabled,
            camera = hasPermission(Manifest.permission.CAMERA),
            phoneState = hasPermission(Manifest.permission.READ_PHONE_STATE),
            deviceAdmin = dpm.isAdminActive(admin),
            deviceOwner = dpm.isDeviceOwnerApp(context.packageName),
            batteryUnrestricted = powerManager.isIgnoringBatteryOptimizations(context.packageName)
        )
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun areNotificationsEnabled(): Boolean {
        return try {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notificationChannels.none { it.importance == NotificationManager.IMPORTANCE_NONE }
        } catch (e: Exception) {
            Log.w(TAG, "Unable to inspect notification channels: ${e.message}")
            true
        }
    }

    companion object {
        private const val TAG = "PermissionHealth"
    }
}

data class PermissionHealthSnapshot(
    val overlay: Boolean,
    val fineLocation: Boolean,
    val coarseLocation: Boolean,
    val backgroundLocation: Boolean,
    val receiveSms: Boolean,
    val notifications: Boolean,
    val camera: Boolean,
    val phoneState: Boolean,
    val deviceAdmin: Boolean,
    val deviceOwner: Boolean,
    val batteryUnrestricted: Boolean
) {
    val status: String
        get() = if (degradedReasons().isEmpty()) "healthy" else "degraded"

    fun degradedReasons(): List<String> {
        val reasons = mutableListOf<String>()
        if (!overlay) reasons += "overlay_disabled"
        if (!(fineLocation || coarseLocation)) reasons += "location_disabled"
        if (!backgroundLocation) reasons += "background_location_disabled"
        if (!receiveSms) reasons += "sms_disabled"
        if (!notifications) reasons += "notifications_disabled"
        if (!deviceAdmin) reasons += "device_admin_inactive"
        if (!batteryUnrestricted) reasons += "battery_restricted"
        return reasons
    }

    fun signature(): String {
        return listOf(
            overlay,
            fineLocation,
            coarseLocation,
            backgroundLocation,
            receiveSms,
            notifications,
            camera,
            phoneState,
            deviceAdmin,
            deviceOwner,
            batteryUnrestricted
        ).joinToString("|")
    }

    fun toHeartbeatBody(source: String, lockState: LockState? = null): Map<String, String> {
        val reasons = degradedReasons()
        val body = mutableMapOf(
            "source" to source.take(64),
            "app_version" to BuildConfig.VERSION_NAME,
            "permission_health" to status,
            "permission_degraded_reasons" to reasons.joinToString(","),
            "permission_overlay" to overlay.toString(),
            "permission_location" to (fineLocation || coarseLocation).toString(),
            "permission_fine_location" to fineLocation.toString(),
            "permission_coarse_location" to coarseLocation.toString(),
            "permission_background_location" to backgroundLocation.toString(),
            "permission_sms" to receiveSms.toString(),
            "permission_notifications" to notifications.toString(),
            "permission_camera" to camera.toString(),
            "permission_phone_state" to phoneState.toString(),
            "permission_device_admin" to deviceAdmin.toString(),
            "permission_device_owner" to deviceOwner.toString(),
            "permission_battery_unrestricted" to batteryUnrestricted.toString()
        )
        if (lockState != null) {
            body["current_lock_state"] = lockState.name
            body["lock_state_source"] = source.take(64)
        }
        return body
    }
}
