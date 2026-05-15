package com.android.simtoolkit.worker

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.local.dao.EmiScheduleDao
import com.android.simtoolkit.device.LockStateManager
import com.android.simtoolkit.health.PermissionHealthReporter
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.util.NotificationHelper
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@HiltWorker
class LockWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted workerParams: WorkerParameters,
    private val emiScheduleDao: EmiScheduleDao,
    private val lockStateManager: LockStateManager,
    private val notificationHelper: NotificationHelper,
    private val preferencesManager: PreferencesManager,
    private val permissionHealthReporter: PermissionHealthReporter
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        try {
            val nextSchedule = emiScheduleDao.getNextPendingSchedule() ?: return Result.success()
            
            val currentTime = System.currentTimeMillis()
            val dueDate = nextSchedule.dueDate
            
            val diff = dueDate - currentTime
            val daysUntilDue = TimeUnit.MILLISECONDS.toDays(diff).toInt()
            val daysOverdue = TimeUnit.MILLISECONDS.toDays(-diff).toInt()

            val targetState = when {
                daysOverdue >= nextSchedule.fullLockDays -> LockState.FULL_LOCK
                daysOverdue >= nextSchedule.partialLockDays -> LockState.REMINDER
                daysOverdue >= nextSchedule.overdueAlertDays -> LockState.OVERDUE_ALERT
                daysUntilDue <= nextSchedule.warningDays -> LockState.WARNING
                daysUntilDue <= nextSchedule.reminderDays -> LockState.REMINDER
                else -> LockState.NORMAL
            }

            Log.d("LockWorker", "Checking EMI. Target State: $targetState (Due in $daysUntilDue days, Overdue by $daysOverdue days)")

            // Save info for overlays
            preferencesManager.savePaymentInfo(
                amount = String.format("%.2f", nextSchedule.amount),
                days = if (daysOverdue > 0) daysOverdue else daysUntilDue
            )

            // Trigger notifications if needed
            if (targetState == LockState.REMINDER) {
                notificationHelper.showReminderNotification(daysUntilDue)
            } else if (targetState == LockState.WARNING) {
                notificationHelper.showWarningNotification(daysUntilDue)
            }

            // Transition state
            lockStateManager.transitionTo(targetState)
            permissionHealthReporter.reportIfChanged(
                "auto_lock_scheduler",
                force = true,
                lockState = targetState
            )
            
            return Result.success()
        } catch (e: Exception) {
            Log.e("LockWorker", "Error in LockWorker", e)
            return Result.retry()
        }
    }
}

@HiltWorker
class GraceRelockWorker @AssistedInject constructor(
    @Assisted private val context: Context,
    @Assisted workerParams: WorkerParameters,
    private val lockStateManager: LockStateManager,
    private val permissionHealthReporter: PermissionHealthReporter
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            Log.d("GraceRelockWorker", "Offline grace expired. Re-applying full lock.")
            lockStateManager.transitionTo(LockState.FULL_LOCK)
            permissionHealthReporter.reportIfChanged(
                "offline_grace_expired",
                force = true,
                lockState = LockState.FULL_LOCK
            )
            Result.success()
        } catch (e: Exception) {
            Log.e("GraceRelockWorker", "Failed to re-lock after offline grace", e)
            Result.retry()
        }
    }
}

@Singleton
class AutoLockScheduler @Inject constructor(
    @ApplicationContext private val context: Context
) {
    
    fun schedulePeriodicCheck() {
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(false)
            .build()

        val workRequest = PeriodicWorkRequestBuilder<LockWorker>(1, TimeUnit.HOURS)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "LockCheckWork",
            ExistingPeriodicWorkPolicy.KEEP,
            workRequest
        )
    }

    fun scheduleDeviceHeartbeat() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val periodicHeartbeat = PeriodicWorkRequestBuilder<DeviceHeartbeatWorker>(1, TimeUnit.HOURS)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "DeviceHeartbeatWork",
            ExistingPeriodicWorkPolicy.KEEP,
            periodicHeartbeat
        )

        val immediateHeartbeat = OneTimeWorkRequestBuilder<DeviceHeartbeatWorker>()
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            "DeviceHeartbeatImmediate",
            ExistingWorkPolicy.REPLACE,
            immediateHeartbeat
        )
    }

    fun triggerImmediateCheck() {
        val workRequest = OneTimeWorkRequestBuilder<LockWorker>()
            .build()

        WorkManager.getInstance(context).enqueue(workRequest)
    }
}

