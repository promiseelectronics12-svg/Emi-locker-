package com.android.simtoolkit.worker

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.health.PermissionHealthReporter
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.firstOrNull

@HiltWorker
class DeviceHeartbeatWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted workerParams: WorkerParameters,
    private val preferencesManager: PreferencesManager,
    private val permissionHealthReporter: PermissionHealthReporter
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val deviceId = preferencesManager.activatedDeviceId.firstOrNull()
        val deviceToken = preferencesManager.deviceToken.firstOrNull()
            ?: preferencesManager.accessToken.firstOrNull()

        if (deviceId.isNullOrBlank() || deviceToken.isNullOrBlank()) {
            Log.d(TAG, "Heartbeat skipped: device is not bound yet")
            return Result.success()
        }

        return try {
            permissionHealthReporter.reportCurrentLockState("workmanager", force = true)
            Log.d(TAG, "Heartbeat accepted for device=$deviceId")
            Result.success()
        } catch (e: Exception) {
            Log.w(TAG, "Heartbeat failed: ${e.message}")
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "DeviceHeartbeatWorker"
    }
}
