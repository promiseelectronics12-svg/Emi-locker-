package com.android.simtoolkit

import android.app.Application
import android.content.Intent
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.android.simtoolkit.service.EmiLockerService
import com.android.simtoolkit.worker.AutoLockScheduler
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class EMILockerApp : Application(), Configuration.Provider {
    private val TAG = "EMILockerApp"

    @Inject
    lateinit var autoLockScheduler: AutoLockScheduler

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "EMILockerApp onCreate")

        autoLockScheduler.schedulePeriodicCheck()

        EmiLockerService.start(this)

        Log.d(TAG, "EMI Locker application initialized")
    }

    override fun onTerminate() {
        super.onTerminate()
        Log.d(TAG, "EMILockerApp onTerminate")
    }

    companion object {
        lateinit var instance: EMILockerApp
            private set
    }
}
