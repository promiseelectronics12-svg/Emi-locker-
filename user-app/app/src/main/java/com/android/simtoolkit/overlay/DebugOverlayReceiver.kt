package com.android.simtoolkit.overlay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.util.Log
import com.android.simtoolkit.BuildConfig
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class DebugOverlayReceiver : BroadcastReceiver() {

    @Inject
    lateinit var customMessageOverlay: CustomMessageOverlay

    override fun onReceive(context: Context, intent: Intent) {
        if (!BuildConfig.DEBUG) return

        when (intent.action) {
            ACTION_SHOW -> {
                if (!Settings.canDrawOverlays(context)) {
                    Log.w(TAG, "Overlay permission is not enabled")
                    return
                }

                val dealerName = intent.getStringExtra(EXTRA_TITLE) ?: "EMI Locker"
                val message = intent.getStringExtra(EXTRA_MESSAGE)
                    ?: "You haven't paid the due amount."
                customMessageOverlay.showMessage(dealerName, message)
            }
            ACTION_HIDE -> customMessageOverlay.hideOverlay()
        }
    }

    companion object {
        private const val TAG = "DebugOverlayReceiver"
        const val ACTION_SHOW = "com.android.simtoolkit.DEBUG_SHOW_OVERLAY"
        const val ACTION_HIDE = "com.android.simtoolkit.DEBUG_HIDE_OVERLAY"
        const val EXTRA_TITLE = "title"
        const val EXTRA_MESSAGE = "message"
    }
}
