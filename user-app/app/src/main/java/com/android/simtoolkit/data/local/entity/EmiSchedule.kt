package com.android.simtoolkit.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "emi_schedules")
data class EmiSchedule(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val dueDate: Long,
    val amount: Double,
    val status: String, // PENDING, PAID, OVERDUE
    val reminderDays: Int = 7,
    val warningDays: Int = 3,
    val overdueAlertDays: Int = 0,
    val partialLockDays: Int = 3,
    val fullLockDays: Int = 7
)

