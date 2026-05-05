package com.android.simtoolkit.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.android.simtoolkit.data.local.dao.EmiScheduleDao
import com.android.simtoolkit.data.local.entity.EmiSchedule

@Database(entities = [EmiSchedule::class], version = 1, exportSchema = false)
abstract class EmiDatabase : RoomDatabase() {
    abstract fun emiScheduleDao(): EmiScheduleDao
}

