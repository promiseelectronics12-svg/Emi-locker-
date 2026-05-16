package com.android.simtoolkit.service

import android.accessibilityservice.AccessibilityService
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.KeyEvent
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.kiosk.AllowedKioskApps
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.overlay.ReminderWatermarkView
import com.android.simtoolkit.presentation.KioskLockActivity
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

@AndroidEntryPoint
class EmiLockerAccessibilityService : AccessibilityService() {

    @Inject lateinit var preferencesManager: PreferencesManager

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var currentLockState: LockState = LockState.NORMAL

    private val wm by lazy { getSystemService(Context.WINDOW_SERVICE) as WindowManager }
    private var watermarkView: View? = null
    private var paymentMonitorJob: Job? = null

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

        private val PAYMENT_PACKAGES = AllowedKioskApps.paymentApps.map { it.packageName }.toSet()

        fun enableSelf(context: Context) {
            Log.d(TAG, "Accessibility auto-enable disabled; kiosk lock screen is used instead")
        }

        fun isEnabled(context: Context): Boolean {
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
                withContext(Dispatchers.Main) {
                    hideWatermark()
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
        hideWatermark()
        scope.cancel()
        super.onDestroy()
    }

    private fun showWatermark() {
        if (watermarkView != null) return
        try {
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            )
            val view = ReminderWatermarkView(this)
            wm.addView(view, params)
            watermarkView = view
            startPaymentMonitor()
            Log.d(TAG, "Watermark shown via TYPE_ACCESSIBILITY_OVERLAY")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show watermark: ${e.message}")
        }
    }

    private fun hideWatermark() {
        stopPaymentMonitor()
        watermarkView?.let { view ->
            try {
                wm.removeView(view)
                Log.d(TAG, "Watermark hidden")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to remove watermark: ${e.message}")
            }
            watermarkView = null
        }
    }

    private fun startPaymentMonitor() {
        paymentMonitorJob?.cancel()
        paymentMonitorJob = scope.launch(Dispatchers.IO) {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            while (isActive) {
                try {
                    val now = System.currentTimeMillis()
                    val events = usm.queryEvents(now - 3000L, now)
                    val event = UsageEvents.Event()
                    var lastForeground: String? = null
                    while (events.hasNextEvent()) {
                        events.getNextEvent(event)
                        if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                            lastForeground = event.packageName
                        }
                    }
                    val isPayment = lastForeground != null && PAYMENT_PACKAGES.contains(lastForeground)
                    withContext(Dispatchers.Main.immediate) {
                        watermarkView?.visibility = if (isPayment) View.INVISIBLE else View.VISIBLE
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Payment monitor: ${e.message}")
                }
                delay(2000L)
            }
        }
    }

    private fun stopPaymentMonitor() {
        paymentMonitorJob?.cancel()
        paymentMonitorJob = null
    }

    private fun isBlockingActive(): Boolean =
        currentLockState == LockState.FULL_LOCK

    private fun isOurPackage(pkg: String): Boolean = pkg == packageName

    private fun isWhitelisted(pkg: String): Boolean =
        CALL_PACKAGES.contains(pkg) ||
                PAYMENT_PACKAGES.contains(pkg) ||
                AllowedKioskApps.settingsPackages.contains(pkg) ||
                AllowedKioskApps.messagingApps.any { it.packageName == pkg } ||
                pkg.startsWith("com.android.systemui")

    private fun bringLockScreenToFront() {
        try {
            val intent = Intent(this, KioskLockActivity::class.java).apply {
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
