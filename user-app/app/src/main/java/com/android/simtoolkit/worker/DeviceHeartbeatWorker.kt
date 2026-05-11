package com.android.simtoolkit.worker

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.firstOrNull

@HiltWorker
class DeviceHeartbeatWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted workerParams: WorkerParameters,
    private val apiService: ApiService,
    private val preferencesManager: PreferencesManager
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val deviceId = preferencesManager.activatedDeviceId.firstOrNull()
        val deviceToken = preferencesManager.deviceToken.firstOrNull()

        if (deviceId.isNullOrBlank() || deviceToken.isNullOrBlank()) {
            Log.d(TAG, "Heartbeat skipped: device is not bound yet")
            return Result.success()
        }

        return try {
            val response = apiService.sendDeviceHeartbeat(
                deviceToken,
                mapOf(
                    "source" to "workmanager",
                    "app_version" to BuildConfig.VERSION_NAME
                )
            )
            if (response.isSuccessful) {
                Log.d(TAG, "Heartbeat accepted for device=$deviceId")
                Result.success()
            } else if (response.code() in 400..499) {
                Log.w(TAG, "Heartbeat rejected code=${response.code()}")
                Result.failure()
            } else {
                Log.w(TAG, "Heartbeat retryable failure code=${response.code()}")
                Result.retry()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Heartbeat failed: ${e.message}")
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "DeviceHeartbeatWorker"
    }
}
