package com.android.simtoolkit.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.presentation.MainActivity
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class EmiLockerAccessibilityService : AccessibilityService() {

    @Inject lateinit var preferencesManager: PreferencesManager

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var currentLockState: LockState = LockState.NORMAL

    companion object {
        private const val TAG = "EmiAccessibilityService"

        private val CALL_PACKAGES = setOf(
            "com.android.dialer",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.oneplus.dialer",
            "com.android.phone",
            "com.android.server.telecom",
            "com.android.contacts",
            "com.google.android.contacts"
        )

        fun enableSelf(context: android.content.Context) {
            val componentName =
                "${context.packageName}/${EmiLockerAccessibilityService::class.java.name}"
            try {
                val cr = context.contentResolver
                val current = Settings.Secure.getString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                if (!current.contains(componentName)) {
                    val updated = if (current.isBlank()) componentName else "$current:$componentName"
                    Settings.Secure.putString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, updated)
                    Settings.Secure.putInt(cr, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
                    Log.d(TAG, "Accessibility service enabled programmatically")
                } else {
                    Log.d(TAG, "Accessibility service already listed in enabled services")
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "WRITE_SECURE_SETTINGS not granted — cannot auto-enable accessibility service. Grant via: adb shell pm grant ${context.packageName} android.permission.WRITE_SECURE_SETTINGS")
            } catch (e: Exception) {
                Log.w(TAG, "Accessibility service auto-enable failed: ${e.message}")
            }
        }

        fun isEnabled(context: android.content.Context): Boolean {
            val componentName =
                "${context.packageName}/${EmiLockerAccessibilityService::class.java.name}"
            return try {
                val enabled = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                ) ?: ""
                enabled.contains(componentName)
            } catch (e: Exception) { false }
        }
    }

    override fun onServiceConnected() {
        Log.d(TAG, "Accessibility service connected")
        scope.launch {
            preferencesManager.currentLockState.collect { stateName ->
                currentLockState = try {
                    if (stateName != null) LockState.valueOf(stateName) else LockState.NORMAL
                } catch (e: IllegalArgumentException) {
                    if (stateName == "PARTIAL_LOCK") LockState.REMINDER else LockState.NORMAL
                }
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isBlockingActive()) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return

        val pkg = event.packageName?.toString() ?: return
        if (isOurPackage(pkg) || isWhitelisted(pkg)) return

        Log.w(TAG, "Blocked app in foreground during FULL_LOCK: $pkg — bringing locker to front")
        bringLockScreenToFront()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!isBlockingActive()) return false
        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_APP_SWITCH -> true  // consume — prevent task switcher
            else -> false
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun isBlockingActive(): Boolean =
        currentLockState == LockState.FULL_LOCK || currentLockState == LockState.OVERDUE_ALERT

    private fun isOurPackage(pkg: String): Boolean = pkg == packageName

    private fun isWhitelisted(pkg: String): Boolean =
        CALL_PACKAGES.contains(pkg) || pkg.startsWith("com.android.systemui")

    private fun bringLockScreenToFront() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bring lock screen to front: ${e.message}")
        }
    }
}
