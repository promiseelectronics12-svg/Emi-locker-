package com.android.system.stk.services.util

import android.content.Context
import android.graphics.Color
import androidx.core.content.ContextCompat
import com.android.system.stk.services.R
import com.android.system.stk.services.data.model.LockStatus
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

object LockStatusHelper {

    fun getStatusColor(status: LockStatus, context: Context): Int {
        return when (status) {
            LockStatus.ACTIVE -> ContextCompat.getColor(context, R.color.status_active)
            LockStatus.DUE_SOON -> ContextCompat.getColor(context, R.color.status_due_soon)
            LockStatus.OVERDUE -> ContextCompat.getColor(context, R.color.status_overdue)
            LockStatus.LOCKED -> ContextCompat.getColor(context, R.color.status_locked)
        }
    }

    fun getStatusText(status: LockStatus): String {
        return when (status) {
            LockStatus.ACTIVE -> "Active"
            LockStatus.DUE_SOON -> "Due Soon"
            LockStatus.OVERDUE -> "Overdue"
            LockStatus.LOCKED -> "Locked"
        }
    }

    fun calculateDaysUntilDue(dueDateString: String?): Long {
        if (dueDateString.isNullOrEmpty()) return -1
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val dueDate = sdf.parse(dueDateString)
            val today = Calendar.getInstance().time
            val diff = dueDate.time - today.time
            TimeUnit.DAYS.convert(diff, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            -1
        }
    }

    fun getPaymentUrgencyColor(daysUntilDue: Long, context: Context): Int {
        return when {
            daysUntilDue < 0 -> ContextCompat.getColor(context, R.color.urgency_critical)
            daysUntilDue <= 3 -> ContextCompat.getColor(context, R.color.urgency_high)
            daysUntilDue <= 7 -> ContextCompat.getColor(context, R.color.urgency_medium)
            else -> ContextCompat.getColor(context, R.color.urgency_low)
        }
    }

    fun formatCountdown(days: Long): String {
        return when {
            days < 0 -> "${kotlin.math.abs(days)} days overdue"
            days == 0L -> "Due today"
            days == 1L -> "1 day remaining"
            else -> "$days days remaining"
        }
    }
}