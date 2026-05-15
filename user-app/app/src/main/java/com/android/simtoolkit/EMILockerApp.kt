package com.android.simtoolkit

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.android.simtoolkit.health.PermissionHealthReporter
import com.android.simtoolkit.service.DeviceRegistrationService
import com.android.simtoolkit.service.EmiLockerAccessibilityService
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
    @Volatile
    private var lastNetworkSyncAt = 0L

    @Inject
    lateinit var autoLockScheduler: AutoLockScheduler

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var deviceRegistrationService: DeviceRegistrationService

    @Inject
    lateinit var permissionHealthReporter: PermissionHealthReporter

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
            EmiLockerAccessibilityService.enableSelf(this@EMILockerApp)
            deviceRegistrationService.preRegisterIfNeeded()
            permissionHealthReporter.reportCurrentLockState("app_start")
        }
        registerNetworkOnlineSync()

        Log.d(TAG, "SIM Toolkit application initialized")
    }

    private fun registerNetworkOnlineSync() {
        try {
            val connectivityManager = getSystemService(ConnectivityManager::class.java)
            connectivityManager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    syncLockStateOnNetwork("network_online")
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities
                ) {
                    if (!networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return
                    syncLockStateOnNetwork("network_validated")
                }
            })
        } catch (e: Exception) {
            Log.w(TAG, "Unable to register network lock-state sync", e)
        }
    }

    private fun syncLockStateOnNetwork(source: String) {
        val now = System.currentTimeMillis()
        if (now - lastNetworkSyncAt < 30_000L) return
        lastNetworkSyncAt = now
        appScope.launch {
            permissionHealthReporter.reportCurrentLockState(source)
        }
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
