package com.emilocker.userapp.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.emilocker.userapp.data.local.dao.EmiScheduleDao
import com.emilocker.userapp.data.local.entity.EmiSchedule

@Database(entities = [EmiSchedule::class], version = 1, exportSchema = false)
abstract class EmiDatabase : RoomDatabase() {
    abstract fun emiScheduleDao(): EmiScheduleDao
}
