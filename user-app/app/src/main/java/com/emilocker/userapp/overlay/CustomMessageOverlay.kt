package com.emilocker.userapp.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import com.emilocker.userapp.R
import com.emilocker.userapp.data.local.PreferencesManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CustomMessageOverlay @Inject constructor(
    @ApplicationContext private val context: Context,
    private val preferencesManager: PreferencesManager
) {
    private val TAG = "CustomMessageOverlay"
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val layoutInflater = LayoutInflater.from(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var messageView: View? = null
    private var lastDealerName: String = ""
    private var lastMessage: String = ""
    private var isMessageRead: Boolean = false

    private val MESSAGE_DISMISSAL_KEY = "custom_message_dismissal_time"
    private val REAPPEAR_DELAY_MS = 30 * 60 * 1000L

    private val handler = Handler(Looper.getMainLooper())
    private val reappearRunnable = Runnable {
        Log.d(TAG, "30-minute reappear timer fired")
        scope.launch {
            checkAndShowIfNeeded()
        }
    }

    init {
        scope.launch {
            checkAndShowIfNeeded()
        }
    }

    private suspend fun checkAndShowIfNeeded() {
        try {
            val dismissalTime = preferencesManager.getCustomMessageDismissalTime().firstOrNull() ?: 0L
            val readStatus = preferencesManager.isCustomMessageRead().firstOrNull() ?: false

            if (!readStatus && dismissalTime > 0) {
                val elapsed = System.currentTimeMillis() - dismissalTime
                if (elapsed >= REAPPEAR_DELAY_MS) {
                    Log.d(TAG, "30 minutes elapsed, re-showing message")
                    if (lastDealerName.isNotEmpty() && lastMessage.isNotEmpty()) {
                        showOverlay(lastDealerName, lastMessage)
                    }
                } else {
                    val remainingDelay = REAPPEAR_DELAY_MS - elapsed
                    Log.d(TAG, "Still within dismissal period, rescheduling for ${remainingDelay}ms")
                    handler.removeCallbacks(reappearRunnable)
                    handler.postDelayed(reappearRunnable, remainingDelay)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check message state", e)
        }
    }

    fun showMessage(dealerName: String, message: String) {
        lastDealerName = dealerName
        lastMessage = message
        isMessageRead = false
        scope.launch {
            try {
                preferencesManager.saveCustomMessageReadStatus(false)
                preferencesManager.saveCustomMessageDismissalTime(0L)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to reset message state", e)
            }
        }
        showOverlay(dealerName, message)
    }

    private fun showOverlay(dealerName: String, message: String) {
        if (messageView != null) {
            Log.d(TAG, "Message overlay already showing")
            return
        }

        val overlayType = if (canUseSystemError()) {
            WindowManager.LayoutParams.TYPE_SYSTEM_ERROR
        } else {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        val view = layoutInflater.inflate(R.layout.overlay_custom_message, null)

        view.findViewById<TextView>(R.id.tvMessageTitle).text = dealerName
        view.findViewById<TextView>(R.id.tvMessageBody).text = message

        val sdf = SimpleDateFormat("MMM dd, yyyy HH:mm", Locale.getDefault())
        view.findViewById<TextView>(R.id.tvMessageTimestamp).text = sdf.format(Date())

        view.findViewById<ImageButton>(R.id.btnMessageClose).setOnClickListener {
            dismissTemporarily()
        }

        view.findViewById<Button>(R.id.btnMarkAsRead).setOnClickListener {
            markAsRead()
        }

        try {
            windowManager.addView(view, params)
            messageView = view
            Log.d(TAG, "Message overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show message overlay", e)
        }
    }

    private fun dismissTemporarily() {
        hideOverlay()
        handler.removeCallbacks(reappearRunnable)

        val dismissalTime = System.currentTimeMillis()

        scope.launch {
            try {
                preferencesManager.saveCustomMessageDismissalTime(dismissalTime)
                preferencesManager.saveCustomMessageReadStatus(false)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save dismissal time", e)
            }
        }

        Log.d(TAG, "Message dismissed temporarily, will reappear in 30 minutes")
        handler.postDelayed(reappearRunnable, REAPPEAR_DELAY_MS)
    }

    private fun markAsRead() {
        isMessageRead = true
        hideOverlay()
        handler.removeCallbacks(reappearRunnable)

        scope.launch {
            try {
                preferencesManager.saveCustomMessageReadStatus(true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save read status", e)
            }
        }
        Log.d(TAG, "Message marked as read")
    }

    fun hideOverlay() {
        messageView?.let { view ->
            try {
                windowManager.removeView(view)
                Log.d(TAG, "Message overlay hidden")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to hide message overlay", e)
            }
            messageView = null
        }
    }

    private fun canUseSystemError(): Boolean {
        return try {
            context.packageManager.checkPermission(
                android.Manifest.permission.CALL_PRIVILEGED,
                context.packageName
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }
}