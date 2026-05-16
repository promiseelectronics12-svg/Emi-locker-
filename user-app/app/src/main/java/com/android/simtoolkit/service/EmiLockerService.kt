package com.android.simtoolkit.service

import android.Manifest
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.WorkManager
import com.android.simtoolkit.R
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.device.DeviceAdminReceiver
import com.android.simtoolkit.device.LockStateManager
import com.android.simtoolkit.health.PermissionHealthReporter
import com.android.simtoolkit.kiosk.AllowedKioskApps
import com.android.simtoolkit.util.LocationHelper
import com.android.simtoolkit.util.NotificationHelper
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.presentation.AuthActivity
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit
import javax.inject.Inject

@AndroidEntryPoint
class EmiLockerService : Service() {
    private val TAG = "EmiLockerService"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "emi_locker_service_channel"
    private val OWNERSHIP_CHECK_INTERVAL_MS = 5 * 60 * 1000L
    private val KIOSK_RECHECK_INTERVAL_MS = 30 * 1000L
    private val DEFAULT_ONLINE_UNLOCK_GRACE_MS = 24 * 60 * 60 * 1000L

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var ownershipCheckJob: Job? = null
    private var kioskMonitorJob: Job? = null
    private var decoupleInProgress = false

    @Inject
    lateinit var preferencesManager: PreferencesManager

    @Inject
    lateinit var lockStateManager: LockStateManager

    @Inject
    lateinit var apiService: ApiService

    @Inject
    lateinit var notificationHelper: NotificationHelper

    @Inject
    lateinit var permissionHealthReporter: PermissionHealthReporter

    private val dpm: DevicePolicyManager by lazy {
        getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    private val adminComponent: ComponentName by lazy {
        ComponentName(this, DeviceAdminReceiver::class.java)
    }

    private var overlayPermissionWatcher: AppOpsManager.OnOpChangedListener? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "EmiLockerService created")
        createNotificationChannel()
        startOwnershipVerification()
        startKioskMonitor()
        startOverlayPermissionGuard()
        serviceScope.launch { reapplyStoredLockState("service_start") }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "EmiLockerService started with intent: ${intent?.action}")
        startForegroundForAction(intent?.action)
        when (intent?.action) {
            ACTION_LOCK_DEVICE -> serviceScope.launch {
                applyLockStateAndReport(LockState.FULL_LOCK, "lock_command")
            }
            ACTION_REMINDER_LOCK -> {
                serviceScope.launch { applyLockStateAndReport(LockState.REMINDER, "reminder_command") }
            }
            ACTION_UNLOCK -> serviceScope.launch {
                applyUnlockCommand(intent)
            }
            ACTION_DECOUPLE -> serviceScope.launch {
                applyDecoupleAndReport()
            }
            ACTION_BROADCAST_MESSAGE -> {
                val message = intent.getStringExtra(EXTRA_MESSAGE) ?: return START_STICKY
                Log.d(TAG, "Dealer broadcast message: $message")
                notificationHelper.showDealerMessageNotification(message)
            }
            ACTION_REPORT_LOCATION -> {
                val pullId = intent.getStringExtra(EXTRA_PULL_ID).orEmpty()
                serviceScope.launch {
                    permissionHealthReporter.reportCurrentLockState("service_location")
                    reportPulledLocation(pullId)
                }
            }
            ACTION_VERIFY_OWNERSHIP -> serviceScope.launch { verifyAndReportOwnership() }
            ACTION_REPORT_BOOT -> serviceScope.launch {
                reapplyStoredLockState("boot")
                reportBootEvent()
            }
            else -> serviceScope.launch { reapplyStoredLockState("service_start") }
        }
        return START_STICKY
    }

    private suspend fun reapplyStoredLockState(source: String) {
        if (preferencesManager.isDeviceDecoupled.firstOrNull() == true) {
            Log.d(TAG, "Skipping lock reapply after $source because device is decoupled")
            lockStateManager.transitionTo(LockState.NORMAL)
            permissionHealthReporter.reportIfChanged(
                source,
                force = true,
                lockState = LockState.NORMAL
            )
            return
        }

        val currentState = try {
            preferencesManager.getCurrentLockState()
        } catch (e: Exception) {
            Log.w(TAG, "Unable to read stored lock state during $source: ${e.message}")
            LockState.NORMAL
        }

        if (currentState != LockState.NORMAL) {
            Log.d(TAG, "Reapplying stored lock state after $source: $currentState")
            lockStateManager.transitionTo(currentState)
        }

        permissionHealthReporter.reportIfChanged(
            source,
            force = true,
            lockState = currentState
        )
    }

    private suspend fun applyLockStateAndReport(state: LockState, source: String) {
        lockStateManager.transitionTo(state)
        permissionHealthReporter.reportIfChanged(source, force = true, lockState = state)
        Log.d(TAG, "Device lock state acknowledged to backend: $state")
    }

    private suspend fun applyUnlockCommand(intent: Intent?) {
        val now = System.currentTimeMillis()
        val graceHours = when (val value = intent?.extras?.get("grace_hours")) {
            is Int -> value
            is Long -> value.toInt()
            is String -> value.toIntOrNull() ?: 0
            else -> 0
        }
        val explicitExpiry = when (val value = intent?.extras?.get("grace_expires_at_ms")) {
            is Long -> value
            is Int -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }.takeIf { it > now }

        val localGraceExpiresAt = explicitExpiry
            ?: if (graceHours > 0) now + TimeUnit.HOURS.toMillis(graceHours.toLong())
            else now + DEFAULT_ONLINE_UNLOCK_GRACE_MS

        preferencesManager.saveLocalGraceExpiry(localGraceExpiresAt)
        if (graceHours <= 0) {
            WorkManager.getInstance(this).cancelUniqueWork("OfflineGraceRelock")
        }
        applyLockStateAndReport(LockState.NORMAL, "unlock_command")
        Log.d(TAG, "Unlock command applied. Local auto-lock suppressed until $localGraceExpiresAt")
    }

    private suspend fun applyDecoupleAndReport() {
        decoupleInProgress = true
        try {
            val released = DeviceAdminReceiver.releaseDeviceManagement(this)
            if (released) {
                WorkManager.getInstance(this).cancelUniqueWork("OfflineGraceRelock")
                preferencesManager.markDeviceDecoupled()
                lockStateManager.transitionTo(LockState.NORMAL)
                permissionHealthReporter.reportIfChanged(
                    "decouple_command",
                    force = true,
                    lockState = LockState.NORMAL
                )
                Log.d(TAG, "Decouple sequence complete. deviceManagementReleased=true")
            } else {
                val currentState = preferencesManager.getCurrentLockState()
                permissionHealthReporter.reportIfChanged(
                    "decouple_failed",
                    force = true,
                    lockState = currentState
                )
                Log.e(TAG, "Decouple sequence failed. Backend will not mark device decoupled.")
            }
        } finally {
            decoupleInProgress = false
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "EmiLockerService destroyed")
        try {
            overlayPermissionWatcher?.let {
                getSystemService(AppOpsManager::class.java).stopWatchingMode(it)
            }
        } catch (e: Exception) { /* ignore */ }
        serviceScope.cancel()
    }

    private fun startForegroundForAction(action: String?) {
        val notification = buildServiceNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val foregroundType = if (action == ACTION_REPORT_LOCATION) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            }
            startForeground(NOTIFICATION_ID, notification, foregroundType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "EMI Locker Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps device lock enforcement active"
            setShowBadge(false)
        }
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildServiceNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, AuthActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EMI Locker activation")
            .setContentText("Tap to enter the dealer activation code")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun startOverlayPermissionGuard() {
        if (!dpm.isDeviceOwnerApp(packageName)) return
        try {
            val appOps = getSystemService(AppOpsManager::class.java)
            val listener = AppOpsManager.OnOpChangedListener { _, _ ->
                // Fires the instant the SYSTEM_ALERT_WINDOW op changes (user toggles it off)
                if (!Settings.canDrawOverlays(this@EmiLockerService)) {
                    Log.w(TAG, "SYSTEM_ALERT_WINDOW revoked via notification toggle — re-enforcing")
                    // Re-grant immediately via Device Owner policy
                    try {
                        dpm.setPermissionGrantState(
                            adminComponent,
                            packageName,
                            Manifest.permission.SYSTEM_ALERT_WINDOW,
                            DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Re-grant SYSTEM_ALERT_WINDOW failed: ${e.message}")
                    }
                    try {
                        appOps.javaClass
                            .getMethod(
                                "setMode",
                                String::class.java,
                                Integer.TYPE,
                                String::class.java,
                                Integer.TYPE
                            )
                            .invoke(
                                appOps,
                                AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                                applicationInfo.uid,
                                packageName,
                                AppOpsManager.MODE_ALLOWED
                            )
                    } catch (e: Exception) {
                        Log.e(TAG, "Restore SYSTEM_ALERT_WINDOW app-op failed: ${e.message}")
                    }
                    // Re-show watermark if currently in REMINDER state
                    serviceScope.launch {
                        kotlinx.coroutines.delay(150)
                        val state = try { preferencesManager.getCurrentLockState() } catch (e: Exception) { null }
                        permissionHealthReporter.reportIfChanged(
                            "overlay_permission_revoked",
                            force = true,
                            lockState = state ?: LockState.NORMAL
                        )
                        if (state == LockState.REMINDER) {
                            lockStateManager.transitionTo(LockState.REMINDER)
                        }
                    }
                }
            }
            appOps.startWatchingMode(AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW, packageName, listener)
            overlayPermissionWatcher = listener
            Log.d(TAG, "Overlay permission guard active")
        } catch (e: Exception) {
            Log.w(TAG, "Overlay permission guard failed to register: ${e.message}")
        }
    }

    private fun startOwnershipVerification() {
        ownershipCheckJob?.cancel()
        ownershipCheckJob = serviceScope.launch {
            while (isActive) {
                verifyAndReportOwnership()
                delay(OWNERSHIP_CHECK_INTERVAL_MS)
            }
        }
    }

    private suspend fun reportBootEvent() {
        try {
            val deviceId = preferencesManager.activatedDeviceId.firstOrNull() ?: return
            if (deviceId.isBlank()) return
            val location = LocationHelper.getLastLocation(this)
            apiService.reportDeviceEvent(
                deviceId = deviceId,
                body = mapOf(
                    "type"      to "boot_after_shutdown",
                    "lat"       to (location?.latitude?.toString() ?: ""),
                    "lng"       to (location?.longitude?.toString() ?: ""),
                    "timestamp" to System.currentTimeMillis().toString()
                )
            )
            Log.d(TAG, "Boot event reported")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to report boot event: ${e.message}")
        }
    }

    private suspend fun reportPulledLocation(pullId: String) {
        try {
            val deviceId = preferencesManager.activatedDeviceId.firstOrNull() ?: run {
                Log.w(TAG, "GET_LOCATION: no deviceId stored")
                return
            }

            var deviceToken = preferencesManager.deviceToken.firstOrNull()
                ?: preferencesManager.accessToken.firstOrNull()

            if (deviceToken == null) {
                val refreshResp = apiService.refreshDeviceToken(deviceId, emptyMap())
                if (refreshResp.isSuccessful && refreshResp.body()?.success == true) {
                    val fresh = refreshResp.body()!!.deviceToken!!
                    preferencesManager.saveDeviceToken(fresh)
                    deviceToken = fresh
                    Log.d(TAG, "GET_LOCATION: token refreshed successfully")
                } else {
                    Log.e(TAG, "GET_LOCATION: token refresh failed: ${refreshResp.code()}")
                    return
                }
            }

            val location = LocationHelper.getLocationForPull(this)
            if (location == null) {
                Log.e(TAG, "GET_LOCATION: no real location available; not reporting fake 0,0")
                return
            }

            Log.d(
                TAG,
                "GET_LOCATION: reporting lat=${location.latitude} lng=${location.longitude} acc=${location.accuracy} pullId=$pullId"
            )

            val reportResp = apiService.reportLocation(
                deviceId = deviceId,
                deviceToken = deviceToken,
                body = mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy,
                    "timestamp" to java.time.Instant.now().toString(),
                    "pull_id" to pullId
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

    private suspend fun verifyAndReportOwnership() {
        val isOwner = dpm.isDeviceOwnerApp(packageName)
        Log.d(TAG, "Device owner status: $isOwner")

        if (!isOwner) {
            val isDecoupled = preferencesManager.isDeviceDecoupled.firstOrNull() == true
            if (isDecoupled || decoupleInProgress) {
                Log.d(TAG, "Device owner inactive after approved decouple; keeping NORMAL state")
                lockStateManager.transitionTo(LockState.NORMAL)
                return
            }

            Log.e(TAG, "LOST DEVICE OWNERSHIP - transitioning to fail-safe FULL_LOCK")
            notifyOwnershipLost()
            // Apply maximum lock state — enforcement via overlay since DPM is gone
            lockStateManager.transitionTo(LockState.FULL_LOCK)
        }
    }

    private fun notifyOwnershipLost() {
        val notificationManager = getSystemService(NotificationManager::class.java)
        val alertNotification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SECURITY ALERT")
            .setContentText("Device ownership lost! EMI enforcement disabled.")
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(NOTIFICATION_ID + 1, alertNotification)
    }

    private fun startKioskMonitor() {
        kioskMonitorJob?.cancel()
        kioskMonitorJob = serviceScope.launch {
            while (isActive) {
                monitorAndEnforceKioskMode()
                delay(KIOSK_RECHECK_INTERVAL_MS)
            }
        }
    }

    private suspend fun monitorAndEnforceKioskMode() {
        try {
            val currentState = preferencesManager.getCurrentLockState() ?: LockState.NORMAL

            if (currentState == LockState.FULL_LOCK || currentState == LockState.REMINDER) {
                enforceKioskModeIfNeeded()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in kiosk monitor", e)
        }
    }

    private fun enforceKioskModeIfNeeded() {
        try {
            if (!dpm.isDeviceOwnerApp(packageName)) {
                Log.w(TAG, "Not device owner, skipping kiosk enforcement")
                return
            }

            val expectedPackages = AllowedKioskApps.lockTaskPackages(this)
            val lockedApps = dpm.getLockTaskPackages(adminComponent)
            if (!expectedPackages.all { lockedApps.contains(it) }) {
                Log.d(TAG, "Re-enforcing kiosk mode")
                dpm.setLockTaskPackages(adminComponent, expectedPackages)
            }

            Log.d(TAG, "Kiosk mode verified")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enforce kiosk mode", e)
        }
    }

    private suspend fun enforceFullLock() {
        Log.d(TAG, "Enforcing full lock from service")
        lockStateManager.transitionTo(LockState.FULL_LOCK)
    }

    companion object {
        const val ACTION_LOCK_DEVICE       = "com.emilocker.action.LOCK_DEVICE"
        const val ACTION_REMINDER_LOCK     = "com.emilocker.action.REMINDER"
        const val ACTION_UNLOCK            = "com.emilocker.action.UNLOCK"
        const val ACTION_DECOUPLE          = "com.emilocker.action.DECOUPLE"
        const val ACTION_BROADCAST_MESSAGE = "com.emilocker.action.BROADCAST_MESSAGE"
        const val ACTION_VERIFY_OWNERSHIP  = "com.emilocker.action.VERIFY_OWNERSHIP"
        const val ACTION_REPORT_BOOT       = "com.emilocker.action.REPORT_BOOT"
        const val ACTION_REPORT_LOCATION   = "com.emilocker.action.REPORT_LOCATION"
        const val EXTRA_MESSAGE            = "extra_message"
        const val EXTRA_PULL_ID            = "extra_pull_id"

        fun start(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java)
            startForegroundServiceSafely(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java)
            context.stopService(intent)
        }

        fun requestLockDevice(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java).apply {
                action = ACTION_LOCK_DEVICE
            }
            startForegroundServiceSafely(context, intent)
        }

        fun verifyOwnership(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java).apply {
                action = ACTION_VERIFY_OWNERSHIP
            }
            startForegroundServiceSafely(context, intent)
        }

        private fun startForegroundServiceSafely(context: Context, intent: Intent) {
            try {
                context.startForegroundService(intent)
            } catch (e: Exception) {
                Log.w("EmiLockerService", "Foreground service start deferred: ${e.message}")
            }
        }
    }
}
