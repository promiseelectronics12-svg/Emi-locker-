package com.android.simtoolkit.data.local.dao

import androidx.room.*
import com.android.simtoolkit.data.local.entity.EmiSchedule
import kotlinx.coroutines.flow.Flow

@Dao
interface EmiScheduleDao {
    @Query("SELECT * FROM emi_schedules ORDER BY dueDate ASC")
    fun getAllSchedules(): Flow<List<EmiSchedule>>

    @Query("SELECT * FROM emi_schedules WHERE status = 'PENDING' OR status = 'OVERDUE' ORDER BY dueDate ASC LIMIT 1")
    suspend fun getNextPendingSchedule(): EmiSchedule?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSchedules(schedules: List<EmiSchedule>)

    @Query("DELETE FROM emi_schedules")
    suspend fun deleteAllSchedules()
}

