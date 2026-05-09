package com.android.simtoolkit.device

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.util.Log
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.presentation.FakeShutdownActivity
import com.android.simtoolkit.util.LocationHelper
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class ShutdownReceiver : BroadcastReceiver() {

    @Inject lateinit var apiService: ApiService
    @Inject lateinit var preferencesManager: PreferencesManager

    private val TAG = "ShutdownReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_SHUTDOWN) return

        Log.d(TAG, "Shutdown detected — launching overlay and capturing location")

        // Show fake shutdown screen (buys 5–8 seconds for GPS + network)
        val overlayIntent = Intent(context, FakeShutdownActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        context.startActivity(overlayIntent)

        // Fire GPS ping in background using goAsync()
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val deviceId = preferencesManager.activatedDeviceId.firstOrNull() ?: ""
                if (deviceId.isBlank()) return@launch

                val location: Location? = LocationHelper.getLastLocation(context)
                apiService.reportDeviceEvent(
                    deviceId = deviceId,
                    body = mapOf(
                        "type"      to "shutdown_detected",
                        "lat"       to (location?.latitude?.toString() ?: ""),
                        "lng"       to (location?.longitude?.toString() ?: ""),
                        "timestamp" to System.currentTimeMillis().toString()
                    )
                )
                Log.d(TAG, "Shutdown event reported: lat=${location?.latitude} lng=${location?.longitude}")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to report shutdown event: ${e.message}")
            } finally {
                pendingResult.finish()
            }
        }
    }
}
