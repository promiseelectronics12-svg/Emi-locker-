package com.android.simtoolkit.service

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
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.android.simtoolkit.R
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.device.DeviceAdminReceiver
import com.android.simtoolkit.device.LockStateManager
import com.android.simtoolkit.util.LocationHelper
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
import javax.inject.Inject

@AndroidEntryPoint
class EmiLockerService : Service() {
    private val TAG = "EmiLockerService"
    private val NOTIFICATION_ID = 1001
    private val CHANNEL_ID = "emi_locker_service_channel"
    private val OWNERSHIP_CHECK_INTERVAL_MS = 5 * 60 * 1000L
    private val KIOSK_RECHECK_INTERVAL_MS = 30 * 1000L

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var ownershipCheckJob: Job? = null
    private var kioskMonitorJob: Job? = null

    @Inject
    lateinit var preferencesManager: PreferencesManager

    @Inject
    lateinit var lockStateManager: LockStateManager

    @Inject
    lateinit var apiService: ApiService

    private val dpm: DevicePolicyManager by lazy {
        getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    private val adminComponent: ComponentName by lazy {
        ComponentName(this, DeviceAdminReceiver::class.java)
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "EmiLockerService created")
        startForegroundWithNotification()
        startOwnershipVerification()
        startKioskMonitor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "EmiLockerService started with intent: ${intent?.action}")
        when (intent?.action) {
            ACTION_LOCK_DEVICE -> serviceScope.launch { lockStateManager.transitionTo(LockState.FULL_LOCK) }
            ACTION_PARTIAL_LOCK -> serviceScope.launch { lockStateManager.transitionTo(LockState.PARTIAL_LOCK) }
            ACTION_UNLOCK -> serviceScope.launch { lockStateManager.transitionTo(LockState.NORMAL) }
            ACTION_DECOUPLE -> serviceScope.launch {
                lockStateManager.transitionTo(LockState.NORMAL)
                Log.d(TAG, "Decouple sequence complete — admin must remove device owner via AMAPI")
            }
            ACTION_BROADCAST_MESSAGE -> {
                val message = intent.getStringExtra(EXTRA_MESSAGE) ?: return START_STICKY
                Log.d(TAG, "Dealer broadcast message: $message")
            }
            ACTION_VERIFY_OWNERSHIP -> serviceScope.launch { verifyAndReportOwnership() }
            ACTION_REPORT_BOOT -> serviceScope.launch { reportBootEvent() }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "EmiLockerService destroyed")
        serviceScope.cancel()
    }

    private fun startForegroundWithNotification() {
        createNotificationChannel()
        val notification = buildServiceNotification()
        startForeground(NOTIFICATION_ID, notification)
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

    private suspend fun verifyAndReportOwnership() {
        val isOwner = dpm.isDeviceOwnerApp(packageName)
        Log.d(TAG, "Device owner status: $isOwner")

        if (!isOwner) {
            Log.e(TAG, "LOST DEVICE OWNERSHIP - Security enforcement compromised!")
            notifyOwnershipLost()
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

            if (currentState == LockState.FULL_LOCK) {
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

            val lockedApps = dpm.getLockTaskPackages(adminComponent)
            if (!lockedApps.contains(packageName)) {
                Log.d(TAG, "Re-enforcing kiosk mode")
                dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
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
        const val ACTION_PARTIAL_LOCK      = "com.emilocker.action.PARTIAL_LOCK"
        const val ACTION_UNLOCK            = "com.emilocker.action.UNLOCK"
        const val ACTION_DECOUPLE          = "com.emilocker.action.DECOUPLE"
        const val ACTION_BROADCAST_MESSAGE = "com.emilocker.action.BROADCAST_MESSAGE"
        const val ACTION_VERIFY_OWNERSHIP  = "com.emilocker.action.VERIFY_OWNERSHIP"
        const val ACTION_REPORT_BOOT       = "com.emilocker.action.REPORT_BOOT"
        const val EXTRA_MESSAGE            = "extra_message"

        fun start(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java)
            context.stopService(intent)
        }

        fun requestLockDevice(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java).apply {
                action = ACTION_LOCK_DEVICE
            }
            context.startForegroundService(intent)
        }

        fun verifyOwnership(context: Context) {
            val intent = Intent(context, EmiLockerService::class.java).apply {
                action = ACTION_VERIFY_OWNERSHIP
            }
            context.startForegroundService(intent)
        }
    }
}
