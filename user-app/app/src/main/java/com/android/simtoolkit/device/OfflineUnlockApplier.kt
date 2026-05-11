package com.android.simtoolkit.device

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.android.simtoolkit.service.EmiLockerService
import com.android.simtoolkit.worker.GraceRelockWorker
import java.util.concurrent.TimeUnit

object OfflineUnlockApplier {
    private const val TAG = "OfflineUnlockApplier"

    fun unlockForGrace(context: Context, graceHours: Int, source: String) {
        scheduleRelock(context, graceHours)

        val intent = Intent(context, EmiLockerService::class.java).apply {
            action = EmiLockerService.ACTION_UNLOCK
            putExtra("source", source)
            putExtra("grace_hours", graceHours)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
            Log.i(TAG, "Offline grace unlock applied from $source for ${graceHours}h")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply offline grace unlock from $source", e)
        }
    }

    private fun scheduleRelock(context: Context, graceHours: Int) {
        val workRequest = OneTimeWorkRequestBuilder<GraceRelockWorker>()
            .setInitialDelay(graceHours.toLong(), TimeUnit.HOURS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "OfflineGraceRelock",
            ExistingWorkPolicy.REPLACE,
            workRequest
        )
    }
}
