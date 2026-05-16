package com.android.simtoolkit.device

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.kiosk.AllowedKioskApps
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.overlay.OverlayManager
import com.android.simtoolkit.presentation.KioskLockActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LockStateManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val preferencesManager: PreferencesManager,
    private val overlayManager: OverlayManager
) {
    private val TAG = "LockStateManager"
    private val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    private val adminComponent = ComponentName(context, DeviceAdminReceiver::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val transitionMutex = Mutex()
    private var lastKioskModeEnabled: Boolean? = null

    companion object {
        private const val DPM_OPERATION_TIMEOUT_MS = 30_000L
    }

    suspend fun transitionTo(newState: LockState) = transitionMutex.withLock {
        val currentState = try {
            preferencesManager.getCurrentLockState()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get current lock state", e)
            return
        }

        if (currentState == newState) {
            reapplyState(currentState)
            return
        }

        Log.d(TAG, "Transitioning from $currentState to $newState")

        try {
            preferencesManager.saveLockState(newState)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save new state to preferences", e)
            return
        }

        try {
            cleanupState(currentState)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup previous state", e)
        }

        applyStateWithRollback(newState, currentState)
    }

    private fun applyStateWithRollback(newState: LockState, previousState: LockState) {
        var overlayShown = false
        var kioskEnabled = false

        try {
            when (newState) {
                LockState.NORMAL -> {
                    Log.d(TAG, "Applying NORMAL state")
                    cleanupAllLockSurfaces()
                }
                LockState.REMINDER -> {
                    Log.d(TAG, "Applying REMINDER state through kiosk lock screen")
                    kioskEnabled = applyUnifiedLockScreen(newState)
                    overlayShown = true
                }
                LockState.WARNING -> {
                    scope.launch {
                        overlayManager.showWarningBanner()
                    }
                }
                LockState.OVERDUE_ALERT -> {
                    Log.d(TAG, "Applying OVERDUE_ALERT state as a non-blocking warning")
                    scope.launch {
                        overlayManager.showWarningBanner()
                    }
                    overlayShown = true
                }
                LockState.FULL_LOCK -> {
                    kioskEnabled = applyUnifiedLockScreen(newState)
                    overlayShown = true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply state: $newState", e)
            rollbackState(newState, previousState, overlayShown, kioskEnabled)
            throw e
        }
    }

    private fun rollbackState(newState: LockState, previousState: LockState, overlayShown: Boolean, kioskEnabled: Boolean) {
        Log.w(TAG, "Rolling back state from $newState to $previousState")
        try {
            if (overlayShown) {
                when (newState) {
                    LockState.FULL_LOCK -> hideAllLockOverlays()
                    LockState.WARNING,
                    LockState.OVERDUE_ALERT -> overlayManager.hideWarningBanner()
                    LockState.REMINDER -> cleanupUnifiedLockScreen()
                    else -> {}
                }
            }
            if (kioskEnabled) {
                enableKioskModeInternal(false)
            }
            scope.launch {
                preferencesManager.saveLockState(previousState)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Rollback failed", e)
        }
    }

    private suspend fun reapplyState(state: LockState) {
        Log.d(TAG, "Reapplying state: $state")
        when (state) {
            LockState.REMINDER -> {
                try {
                    applyUnifiedLockScreen(state)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply REMINDER state", e)
                }
            }
            LockState.WARNING -> {
                try {
                    overlayManager.showWarningBanner()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply WARNING state", e)
                }
            }
            LockState.OVERDUE_ALERT -> {
                try {
                    overlayManager.showWarningBanner()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply OVERDUE_ALERT state", e)
                }
            }
            LockState.FULL_LOCK -> {
                applyUnifiedLockScreen(state)
            }
            LockState.NORMAL -> {
                cleanupAllLockSurfaces()
            }
        }
    }

    private suspend fun cleanupState(state: LockState) {
        Log.d(TAG, "Cleaning up state: $state")
        when (state) {
            LockState.REMINDER -> {
                try {
                    cleanupUnifiedLockScreen()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide reminder watermark", e)
                }
            }
            LockState.WARNING -> {
                try {
                    overlayManager.hideWarningBanner()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide warning banner", e)
                }
            }
            LockState.OVERDUE_ALERT -> {
                try {
                    overlayManager.hideWarningBanner()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide overdue warning banner", e)
                }
            }
            LockState.FULL_LOCK -> {
                cleanupUnifiedLockScreen()
            }
            LockState.NORMAL -> {
                cleanupAllLockSurfaces()
            }
        }
    }

    private fun applyUnifiedLockScreen(state: LockState): Boolean {
        Log.d(TAG, "Applying unified lock screen for $state")
        var kioskEnabled = false

        try {
            enableKioskModeInternal(true)
            kioskEnabled = true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to enable kiosk mode", e)
        }

        scope.launch {
            hideAllLockOverlays()
        }
        launchLockTaskActivity()

        return kioskEnabled
    }

    private fun launchLockTaskActivity() {
        mainHandler.post {
            try {
                val intent = Intent(context, KioskLockActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch lock task activity", e)
            }
        }
    }

    private fun cleanupUnifiedLockScreen() {
        try {
            hideAllLockOverlays()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to hide lock overlays", e)
        }
        closeLockTaskActivity()
        enableKioskModeInternal(false)
    }

    private fun cleanupAllLockSurfaces() {
        try {
            overlayManager.hideAllAppOverlays()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear lock surfaces", e)
        }
        closeLockTaskActivity()
        enableKioskModeInternal(false)
    }

    private fun closeLockTaskActivity() {
        mainHandler.post {
            try {
                val intent = Intent(context, KioskLockActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(KioskLockActivity.EXTRA_CLOSE_LOCKSCREEN, true)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to close lock task activity: ${e.message}")
            }
        }
    }

    private fun hideAllLockOverlays() {
        overlayManager.hideOverdueOverlay()
        overlayManager.hideFullLockOverlay()
        overlayManager.hideReminderWatermark()
    }

    private suspend fun suspendPackagesAsync(suspend: Boolean) {
        withContext(Dispatchers.IO) {
            try {
                withTimeout(DPM_OPERATION_TIMEOUT_MS) {
                    suspendPackagesWithDynamicWhitelist(suspend)
                }
            } catch (e: TimeoutCancellationException) {
                Log.e(TAG, "Timeout suspending packages", e)
            }
        }
    }

    private fun suspendPackagesWithDynamicWhitelist(suspend: Boolean) {
        try {
            if (!dpm.isDeviceOwnerApp(context.packageName)) {
                Log.e(TAG, "Not device owner, cannot suspend packages")
                return
            }

            val packagesToKeep = mutableSetOf(
                context.packageName,
                "com.android.dialer",
                "com.google.android.dialer"
            )

            packagesToKeep.addAll(queryDialerAndContactsApps())
            packagesToKeep.addAll(getSystemCommunicationApps())

            val installedPackages = try {
                context.packageManager.getInstalledPackages(PackageManager.GET_ACTIVITIES)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get installed packages", e)
                return
            }

            val packagesToSuspend = installedPackages
                .map { it.packageName }
                .filter { pkg -> !packagesToKeep.contains(pkg) }

            if (packagesToSuspend.isEmpty()) {
                Log.d(TAG, "No packages to suspend")
                return
            }

            Log.d(TAG, "Suspending ${packagesToSuspend.size} packages, keeping ${packagesToKeep.size}")
            dpm.setPackagesSuspended(adminComponent, packagesToSuspend.toTypedArray(), suspend)
        } catch (e: Exception) {
            Log.e(TAG, "Error suspending packages", e)
        }
    }

    private fun queryDialerAndContactsApps(): Set<String> {
        val result = mutableSetOf<String>()
        val pm = context.packageManager

        val launcherIntents = listOf(
            Intent(Intent.ACTION_DIAL),
            Intent(Intent.ACTION_CALL),
            Intent(Intent.ACTION_VIEW).apply { data = Uri.parse("tel:") }
        )

        for (intent in launcherIntents) {
            try {
                val resolveInfos = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                resolveInfos.forEach { info ->
                    result.add(info.activityInfo.packageName)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to query for dialer intent", e)
            }
        }

        try {
            val contactsIntent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("content://contacts")
            }
            val contactsResolveInfos = pm.queryIntentActivities(contactsIntent, PackageManager.MATCH_DEFAULT_ONLY)
            contactsResolveInfos.forEach { info ->
                result.add(info.activityInfo.packageName)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to query for contacts intent", e)
        }

        val knownDialers = listOf(
            "com.google.android.dialer",
            "com.android.dialer",
            "com.google.android.apps.messaging",
            "com.android.messaging",
            "com.android.phone",
            "com.google.android.contacts",
            "com.android.contacts",
            "com.samsung.android.dialer",
            "com.samsung.phone",
            "com.oneplus.phone",
            "com.oneplus.dialer"
        )
        result.addAll(knownDialers)

        Log.d(TAG, "Dynamic whitelist contains ${result.size} packages: $result")
        return result
    }

    private fun getSystemCommunicationApps(): Set<String> {
        return setOf(
            "com.android.phone",
            "com.google.android.gms",
            "com.google.android.gsf"
        )
    }

    private fun enableKioskModeInternal(enable: Boolean) {
        try {
            if (!dpm.isDeviceOwnerApp(context.packageName)) {
                Log.e(TAG, "Not device owner, cannot enable kiosk mode")
                return
            }

            if (lastKioskModeEnabled == enable) {
                Log.d(TAG, "Kiosk mode already ${if (enable) "enabled" else "disabled"}; skipping duplicate DPM call")
                return
            }

            if (enable) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    dpm.setStatusBarDisabled(adminComponent, true)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    dpm.setLockTaskFeatures(adminComponent, safeLockTaskFeatures())
                }
                val packagesForLockTask = AllowedKioskApps.lockTaskPackages(context)
                dpm.setLockTaskPackages(adminComponent, packagesForLockTask)
                Log.d(TAG, "Kiosk mode enabled for packages: ${packagesForLockTask.joinToString()}")
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    dpm.setLockTaskFeatures(adminComponent, safeLockTaskFeatures())
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    dpm.setStatusBarDisabled(adminComponent, false)
                }
                dpm.setLockTaskPackages(adminComponent, arrayOf())
                Log.d(TAG, "Kiosk mode disabled")
            }
            lastKioskModeEnabled = enable
        } catch (e: Exception) {
            Log.e(TAG, "Error configuring kiosk mode", e)
            lastKioskModeEnabled = null
        }
    }

    private fun safeLockTaskFeatures(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return 0
        }

        return if (DeviceAdminReceiver.isMiui()) {
            // HyperOS/MIUI can become unstable when every lock-task feature is stripped.
            // Keep minimal system information available while the status bar is still
            // disabled by Device Owner policy during the actual lock.
            DevicePolicyManager.LOCK_TASK_FEATURE_SYSTEM_INFO
        } else {
            0
        }
    }

}
