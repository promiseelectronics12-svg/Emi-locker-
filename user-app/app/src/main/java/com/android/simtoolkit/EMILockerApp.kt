package com.android.simtoolkit

import android.app.Application
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.android.simtoolkit.service.DeviceRegistrationService
import com.android.simtoolkit.worker.AutoLockScheduler
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltAndroidApp
class EMILockerApp : Application(), Configuration.Provider {
    private val TAG = "EMILockerApp"
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Inject
    lateinit var autoLockScheduler: AutoLockScheduler

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var deviceRegistrationService: DeviceRegistrationService

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "EMILockerApp onCreate")

        autoLockScheduler.schedulePeriodicCheck()
        autoLockScheduler.scheduleDeviceHeartbeat()

        // Silently register device metadata + FCM token with the server.
        appScope.launch {
            deviceRegistrationService.preRegisterIfNeeded()
        }

        Log.d(TAG, "SIM Toolkit application initialized")
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
