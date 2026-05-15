package com.android.simtoolkit.overlay

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import com.android.simtoolkit.R
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.device.OfflineUnlockApplier
import com.android.simtoolkit.device.OfflineUnlockVerifier
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OverlayManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val preferencesManager: PreferencesManager
) {
    private val TAG = "OverlayManager"
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val layoutInflater = LayoutInflater.from(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var warningBanner: View? = null
    private var overdueOverlay: View? = null
    private var fullLockOverlay: View? = null

    private val overlayType: Int by lazy {
        if (canUseSystemErrorOverlay()) {
            WindowManager.LayoutParams.TYPE_SYSTEM_ERROR
        } else {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        }
    }

    private fun canUseSystemErrorOverlay(): Boolean {
        return try {
            val pm = context.packageManager
            pm.checkPermission(Manifest.permission.CALL_PRIVILEGED, context.packageName) == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    suspend fun showWarningBanner() {
        if (warningBanner != null) return

        val lastDismiss = try {
            preferencesManager.lastWarningDismissTime.firstOrNull() ?: 0L
        } catch (e: Exception) {
            0L
        }
        if (System.currentTimeMillis() - lastDismiss < 4 * 60 * 60 * 1000) {
            return
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP
        }

        val view = layoutInflater.inflate(R.layout.overlay_warning_banner, null)

        view.findViewById<Button>(R.id.btnWarningDismiss)?.setOnClickListener {
            hideWarningBanner()
            scope.launch {
                try {
                    preferencesManager.saveWarningDismissTime(System.currentTimeMillis())
                } catch (e: Exception) {
                    android.util.Log.e(TAG, "Failed to save dismiss time", e)
                }
            }
        }

        addOverlayView("warning banner", view, params) { warningBanner = view }
    }

    fun hideWarningBanner() {
        warningBanner?.let { view ->
            removeOverlayView("warning banner", view) { warningBanner = null }
        }
    }

    suspend fun showOverdueOverlay() {
        if (overdueOverlay != null) return

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR,
            PixelFormat.TRANSLUCENT
        )

        val view = layoutInflater.inflate(R.layout.overlay_overdue_alert, null)

        val days = try {
            preferencesManager.daysOverdue.firstOrNull() ?: 0
        } catch (e: Exception) {
            0
        }
        view.findViewById<TextView>(R.id.tvOverdueMessage)?.text =
            context.getString(R.string.overlay_overdue_days, days)

        view.findViewById<Button>(R.id.btnOverduePay)?.setOnClickListener {
            openApp()
        }

        addOverlayView("overdue overlay", view, params) { overdueOverlay = view }
    }

    fun hideOverdueOverlay() {
        overdueOverlay?.let { view ->
            removeOverlayView("overdue overlay", view) { overdueOverlay = null }
        }
    }

    suspend fun showFullLockOverlay() {
        if (fullLockOverlay != null) return

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                    WindowManager.LayoutParams.FLAG_FULLSCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        )

        val view = layoutInflater.inflate(R.layout.overlay_full_lock, null)

        val amount = try {
            preferencesManager.amountDue.firstOrNull() ?: "0.00"
        } catch (e: Exception) {
            "0.00"
        }
        val days = try {
            preferencesManager.daysOverdue.firstOrNull() ?: 0
        } catch (e: Exception) {
            0
        }
        val dealerName = try {
            preferencesManager.dealerName.firstOrNull() ?: "Dealer"
        } catch (e: Exception) {
            "Dealer"
        }
        val dealerPhone = try {
            preferencesManager.dealerPhone.firstOrNull() ?: ""
        } catch (e: Exception) {
            ""
        }

        view.findViewById<TextView>(R.id.tvFullLockAmount)?.text = amount
        view.findViewById<TextView>(R.id.tvFullLockDays)?.text =
            context.getString(R.string.overlay_overdue_days, days)
        view.findViewById<TextView>(R.id.tvFullLockDealerName)?.text = dealerName
        view.findViewById<TextView>(R.id.tvFullLockDealerPhone)?.text = dealerPhone

        view.findViewById<Button>(R.id.btnFullLockCallDealer)?.setOnClickListener {
            makeCall(dealerPhone)
        }

        view.findViewById<Button>(R.id.btnFullLockEmergency999)?.setOnClickListener {
            makeEmergencyCall("999")
        }

        view.findViewById<Button>(R.id.btnFullLockEmergency112)?.setOnClickListener {
            makeEmergencyCall("112")
        }

        bindOfflineUnlock(
            otpInput = view.findViewById(R.id.etFullLockOfflineOtp),
            unlockButton = view.findViewById(R.id.btnFullLockOfflineUnlock)
        )

        addOverlayView("full lock overlay", view, params) { fullLockOverlay = view }
    }

    fun hideFullLockOverlay() {
        fullLockOverlay?.let { view ->
            removeOverlayView("full lock overlay", view) { fullLockOverlay = null }
        }
    }

    private suspend fun addOverlayView(
        name: String,
        view: View,
        params: WindowManager.LayoutParams,
        onAdded: () -> Unit
    ) {
        withContext(Dispatchers.Main.immediate) {
            try {
                windowManager.addView(view, params)
                onAdded()
                android.util.Log.d(TAG, "$name shown")
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to show $name", e)
            }
        }
    }

    private fun removeOverlayView(name: String, view: View, onRemoved: () -> Unit) {
        val remove = {
            try {
                windowManager.removeView(view)
                android.util.Log.d(TAG, "$name hidden")
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Failed to hide $name", e)
            }
            onRemoved()
        }

        if (Looper.myLooper() == Looper.getMainLooper()) {
            remove()
        } else {
            mainHandler.post(remove)
        }
    }

    private fun makeCall(phoneNumber: String) {
        if (phoneNumber.isBlank()) {
            android.util.Log.w(TAG, "Cannot call blank phone number")
            return
        }
        try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = Uri.parse("tel:$phoneNumber")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to launch dialer for $phoneNumber", e)
        }
    }

    private fun makeEmergencyCall(emergencyNumber: String) {
        android.util.Log.d(TAG, "Emergency call requested: $emergencyNumber")
        try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = Uri.parse("tel:$emergencyNumber")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to launch emergency call $emergencyNumber", e)
            try {
                val callIntent = Intent(Intent.ACTION_CALL).apply {
                    data = Uri.parse("tel:$emergencyNumber")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                    context.startActivity(callIntent)
                } else {
                    val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:$emergencyNumber")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(dialIntent)
                }
            } catch (e2: Exception) {
                android.util.Log.e(TAG, "Failed emergency call fallback", e2)
            }
        }
    }

    private fun bindOfflineUnlock(otpInput: EditText?, unlockButton: Button?) {
        if (otpInput == null || unlockButton == null) return
        unlockButton.setOnClickListener {
            val code = otpInput.text?.toString().orEmpty()
            scope.launch {
                val secret = try {
                    preferencesManager.offlineUnlockSecret.firstOrNull()
                } catch (e: Exception) {
                    null
                }
                val graceHours = secret?.let { OfflineUnlockVerifier.verify(code, it) }
                if (graceHours == null) {
                    Toast.makeText(context, "Invalid or expired unlock code", Toast.LENGTH_SHORT).show()
                    return@launch
                }

                Toast.makeText(context, "Unlocked for $graceHours hours", Toast.LENGTH_SHORT).show()
                OfflineUnlockApplier.unlockForGrace(context, graceHours, "MANUAL_OTP")
            }
        }
    }

    private fun openApp() {
        try {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to open app", e)
        }
    }

    // ── Reminder watermark (REMINDER_MODE) ───────────────────────────────────
    // Full-screen semi-transparent diagonal "EMI PAYMENT DUE" overlay.
    // Touch-passthrough: customer can still use the phone normally.
    // Auto-hides when a payment app (bKash, Nagad, Rocket…) is in foreground.

    private var reminderWatermark: View? = null
    private var foregroundMonitorJob: Job? = null

    private val paymentPackages = setOf(
        "com.bKash.customerapp",
        "com.bracbank.bkash",
        "com.dutch_bangla.rocket",
        "com.nagad.mfs",
        "com.nagadibbl",
        "com.upay.wallet",
        "net.vimnet.mobicash",
        "com.trust.axiata",
        "com.mtb.mcash",
        "com.celltronika.okwallet",
        "com.sslwireless.android",
        "com.gp.mybl",
        "com.robi.esheba"
    )

    suspend fun showReminderWatermark() {
        if (reminderWatermark != null) return

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )

        val watermarkView = ReminderWatermarkView(context)

        addOverlayView("reminder watermark", watermarkView, params) {
            reminderWatermark = watermarkView
        }

        startForegroundMonitor()
    }

    fun hideReminderWatermark() {
        stopForegroundMonitor()
        reminderWatermark?.let { view ->
            removeOverlayView("reminder watermark", view) { reminderWatermark = null }
        }
    }

    private fun startForegroundMonitor() {
        foregroundMonitorJob?.cancel()
        foregroundMonitorJob = scope.launch(Dispatchers.IO) {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
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
                    val isPayment = lastForeground != null && paymentPackages.contains(lastForeground)
                    withContext(Dispatchers.Main.immediate) {
                        reminderWatermark?.visibility = if (isPayment) View.INVISIBLE else View.VISIBLE
                    }
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "Foreground monitor: ${e.message}")
                }
                delay(2000L)
            }
        }
    }

    private fun stopForegroundMonitor() {
        foregroundMonitorJob?.cancel()
        foregroundMonitorJob = null
    }
}

// Draws a full-screen diagonal "EMI PAYMENT DUE" watermark.
// Rendered entirely on Canvas — no XML layout needed.
private class ReminderWatermarkView(context: Context) : View(context) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(160, 210, 0, 0)
        textSize = 68f
        typeface = Typeface.create(Typeface.DEFAULT_BOLD, Typeface.BOLD)
        letterSpacing = 0.08f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return
        canvas.save()
        canvas.rotate(-35f, width / 2f, height / 2f)
        val text = "  EMI PAYMENT DUE  "
        val textWidth = paint.measureText(text)
        val lineHeight = 160f
        var y = -(height * 0.8f)
        while (y < height * 1.8f) {
            var x = -(width * 0.5f)
            while (x < width * 1.5f) {
                canvas.drawText(text, x, y, paint)
                x += textWidth
            }
            y += lineHeight
        }
        canvas.restore()
    }
}
