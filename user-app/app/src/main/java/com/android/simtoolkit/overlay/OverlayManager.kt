package com.android.simtoolkit.overlay

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.firstOrNull
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
    private var partialLockOverlay: View? = null
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

    suspend fun showPartialLockOverlay() {
        if (partialLockOverlay != null) return

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )

        val view = layoutInflater.inflate(R.layout.overlay_partial_lock, null)

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

        view.findViewById<TextView>(R.id.tvPartialLockAmount)?.text = amount
        view.findViewById<TextView>(R.id.tvPartialLockDays)?.text =
            context.getString(R.string.overlay_overdue_days, days)
        view.findViewById<TextView>(R.id.tvPartialLockDealerName)?.text = dealerName
        view.findViewById<TextView>(R.id.tvPartialLockDealerPhone)?.text = dealerPhone

        view.findViewById<Button>(R.id.btnPartialLockCallDealer)?.setOnClickListener {
            makeCall(dealerPhone)
        }

        view.findViewById<Button>(R.id.btnPartialLockEmergency)?.setOnClickListener {
            makeEmergencyCall("999")
        }

        view.findViewById<Button>(R.id.btnPartialLockPay)?.setOnClickListener {
            openApp()
        }

        bindOfflineUnlock(
            otpInput = view.findViewById(R.id.etPartialLockOfflineOtp),
            unlockButton = view.findViewById(R.id.btnPartialLockOfflineUnlock)
        )

        addOverlayView("partial lock overlay", view, params) { partialLockOverlay = view }
    }

    fun hidePartialLockOverlay() {
        partialLockOverlay?.let { view ->
            removeOverlayView("partial lock overlay", view) { partialLockOverlay = null }
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
                    WindowManager.LayoutParams.FLAG_FULLSCREEN,
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
}
