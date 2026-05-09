package com.android.simtoolkit.device

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.service.EmiLockerService

class DeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "EmiDeviceAdminReceiver"

        fun isDeviceOwner(context: Context): Boolean {
            return try {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                dpm.isDeviceOwnerApp(context.packageName)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to check device owner status", e)
                false
            }
        }

        fun getAdminComponent(context: Context): ComponentName {
            return ComponentName(context, DeviceAdminReceiver::class.java)
        }
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Device Admin enabled — applying policies")
        applyDeviceOwnerPolicies(context)
        EmiLockerService.start(context)
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        if (BuildConfig.DEBUG) {
            Log.w(TAG, "Device admin disable requested in debug build; no lock action taken")
            return "EMI Locker device admin is being disabled for testing."
        }

        Log.e(TAG, "Disable requested — re-locking device to prevent removal")
        try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.lockNow()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to lock device", e)
        }
        return ""
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.e(TAG, "Device Admin DISABLED — attempting service restart")
        EmiLockerService.start(context)
    }

    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.d(TAG, "Provisioning complete — starting EMI Locker")
        applyDeviceOwnerPolicies(context)
        EmiLockerService.start(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            Log.d(TAG, "Boot completed — restarting EmiLockerService")
            EmiLockerService.start(context)
        }
    }

    private fun applyDeviceOwnerPolicies(context: Context) {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(context, DeviceAdminReceiver::class.java)
        if (!dpm.isDeviceOwnerApp(context.packageName)) return
        try {
            dpm.setGlobalSetting(adminComponent, android.provider.Settings.Global.ADB_ENABLED, "0")
            dpm.setGlobalSetting(adminComponent, android.provider.Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, "0")
            dpm.setSecureSetting(adminComponent, android.provider.Settings.Secure.INSTALL_NON_MARKET_APPS, "0")
            dpm.setUninstallBlocked(adminComponent, context.packageName, true)
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_FACTORY_RESET)
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_POWER_OFF)
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_SAFE_BOOT)
            Log.d(TAG, "Device Owner policies applied successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply Device Owner policies", e)
        }
    }
}

class BootCompletedReceiver : BroadcastReceiver() {
    private val TAG = "BootCompletedReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.d(TAG, "Boot completed, starting EMI Locker service")
            try {
                EmiLockerService.start(context)
                // Report boot event with GPS (picks up last known location)
                val bootIntent = Intent(context, EmiLockerService::class.java).apply {
                    action = EmiLockerService.ACTION_REPORT_BOOT
                }
                context.startForegroundService(bootIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start service on boot", e)
            }
        }
    }
}
