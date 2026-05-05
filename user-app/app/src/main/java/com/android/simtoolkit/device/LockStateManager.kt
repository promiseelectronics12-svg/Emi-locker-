package com.android.simtoolkit.device

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.overlay.OverlayManager
import com.android.simtoolkit.ui.dealer.DealerContactActivity
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

    companion object {
        private const val KIOSK_ENABLE_DELAY_MS = 2500L
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
                }
                LockState.REMINDER -> {
                    Log.d(TAG, "Applying REMINDER state")
                }
                LockState.WARNING -> {
                    scope.launch {
                        overlayManager.showWarningBanner()
                    }
                }
                LockState.OVERDUE_ALERT -> {
                    scope.launch {
                        overlayManager.showOverdueOverlay()
                    }
                }
                LockState.PARTIAL_LOCK -> {
                    suspendPackagesAsync(true)
                    scope.launch {
                        overlayManager.showPartialLockOverlay()
                    }
                }
                LockState.FULL_LOCK -> {
                    scope.launch {
                        overlayManager.showFullLockOverlay()
                        overlayShown = true
                    }
                    mainHandler.postDelayed({
                        try {
                            enableKioskModeInternal(true)
                            kioskEnabled = true
                            dpm.lockNow()
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to enable kiosk mode or lock device", e)
                        }
                    }, KIOSK_ENABLE_DELAY_MS)
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
                    LockState.FULL_LOCK -> overlayManager.hideFullLockOverlay()
                    LockState.PARTIAL_LOCK -> overlayManager.hidePartialLockOverlay()
                    LockState.OVERDUE_ALERT -> overlayManager.hideOverdueOverlay()
                    LockState.WARNING -> overlayManager.hideWarningBanner()
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
            LockState.WARNING -> {
                try {
                    overlayManager.showWarningBanner()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply WARNING state", e)
                }
            }
            LockState.OVERDUE_ALERT -> {
                try {
                    overlayManager.showOverdueOverlay()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply OVERDUE_ALERT state", e)
                }
            }
            LockState.PARTIAL_LOCK -> {
                suspendPackagesAsync(true)
                try {
                    overlayManager.showPartialLockOverlay()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply PARTIAL_LOCK state", e)
                }
            }
            LockState.FULL_LOCK -> {
                try {
                    overlayManager.showFullLockOverlay()
                    enableKioskModeInternal(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to reapply FULL_LOCK state", e)
                }
            }
            else -> {}
        }
    }

    private suspend fun cleanupState(state: LockState) {
        Log.d(TAG, "Cleaning up state: $state")
        when (state) {
            LockState.WARNING -> {
                try {
                    overlayManager.hideWarningBanner()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide warning banner", e)
                }
            }
            LockState.OVERDUE_ALERT -> {
                try {
                    overlayManager.hideOverdueOverlay()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide overdue overlay", e)
                }
            }
            LockState.PARTIAL_LOCK -> {
                suspendPackagesAsync(false)
                try {
                    overlayManager.hidePartialLockOverlay()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide partial lock overlay", e)
                }
            }
            LockState.FULL_LOCK -> {
                try {
                    overlayManager.hideFullLockOverlay()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to hide full lock overlay", e)
                }
                enableKioskModeInternal(false)
            }
            else -> {}
        }
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
            packagesToKeep.addAll(getEmergencyDialerPackages())

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

    private fun getEmergencyDialerPackages(): Set<String> {
        val result = mutableSetOf<String>()
        val pm = context.packageManager

        val emergencyNumbers = listOf("tel:999", "tel:112")
        for (number in emergencyNumbers) {
            try {
                val intent = Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse(number)
                }
                val resolveInfos = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                resolveInfos.forEach { info ->
                    result.add(info.activityInfo.packageName)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to resolve emergency number $number", e)
            }
        }

        result.add("com.android.dialer")
        result.add("com.google.android.dialer")
        result.add("com.samsung.android.dialer")

        return result
    }

    private fun enableKioskModeInternal(enable: Boolean) {
        try {
            if (!dpm.isDeviceOwnerApp(context.packageName)) {
                Log.e(TAG, "Not device owner, cannot enable kiosk mode")
                return
            }

            if (enable) {
                dpm.setLockTaskFeatures(adminComponent, 0)
                val packagesForLockTask = arrayOf(
                    context.packageName,
                    "com.android.dialer",
                    "com.google.android.dialer",
                    "com.samsung.android.dialer",
                    "com.android.phone",
                    "com.android.server.telecom"
                )
                dpm.setLockTaskPackages(adminComponent, packagesForLockTask)
                Log.d(TAG, "Kiosk mode enabled for packages: ${packagesForLockTask.joinToString()}")
            } else {
                dpm.setLockTaskPackages(adminComponent, arrayOf())
                Log.d(TAG, "Kiosk mode disabled")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error configuring kiosk mode", e)
        }
    }

    fun setEmergencyDialerAsDefault() {
        try {
            if (!dpm.isDeviceOwnerApp(context.packageName)) {
                Log.e(TAG, "Not device owner, cannot set default launcher")
                return
            }

            val emergencyDialerPackages = listOf(
                "com.android.dialer",
                "com.google.android.dialer",
                "com.samsung.android.dialer"
            )

            for (pkg in emergencyDialerPackages) {
                try {
                    val intent = Intent(Intent.ACTION_DIAL).apply {
                        setPackage(pkg)
                    }
                    val resolveInfo = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
                    if (resolveInfo != null) {
                        val componentName = ComponentName(pkg, resolveInfo.activityInfo.name)

                        val filter = android.content.IntentFilter().apply {
                            addAction(Intent.ACTION_DIAL)
                            addCategory(Intent.CATEGORY_DEFAULT)
                        }

                        dpm.addPersistentPreferredActivity(adminComponent, filter, componentName)
                        Log.d(TAG, "Added $pkg as persistent preferred activity for emergency calls")
                        break
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to set $pkg as default dialer", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set emergency dialer as default", e)
        }
    }

    fun clearEmergencyDialerDefault() {
        try {
            if (!dpm.isDeviceOwnerApp(context.packageName)) {
                return
            }
            dpm.clearPackagePersistentPreferredActivities(adminComponent, "com.android.dialer")
            dpm.clearPackagePersistentPreferredActivities(adminComponent, "com.google.android.dialer")
            Log.d(TAG, "Cleared emergency dialer defaults")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear emergency dialer defaults", e)
        }
    }
}
