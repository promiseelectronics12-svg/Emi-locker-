package com.android.simtoolkit.device

import android.annotation.SuppressLint
import android.app.admin.DeviceAdminReceiver as AndroidDeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.UserManager
import android.util.Log
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.service.EmiLockerService

class DeviceAdminReceiver : AndroidDeviceAdminReceiver() {

    companion object {
        private const val TAG = "EmiDeviceAdminReceiver"
        private const val DISALLOW_POWER_OFF_RESTRICTION = "no_power_off"

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

        fun isMiui(): Boolean {
            return try {
                val systemProperties = Class.forName("android.os.SystemProperties")
                val get = systemProperties.getMethod(
                    "get",
                    String::class.java,
                    String::class.java
                )
                val miuiVersion = get.invoke(null, "ro.miui.ui.version.name", "") as String
                val hyperOsVersion = get.invoke(null, "ro.mi.os.version.name", "") as String
                miuiVersion.isNotEmpty() || hyperOsVersion.isNotEmpty()
            } catch (e: Exception) {
                false
            }
        }

        @SuppressLint("NewApi")
        fun releaseDeviceManagement(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = getAdminComponent(context)
            val restrictions = listOf(
                UserManager.DISALLOW_FACTORY_RESET,
                DISALLOW_POWER_OFF_RESTRICTION,
                UserManager.DISALLOW_SAFE_BOOT,
                UserManager.DISALLOW_DEBUGGING_FEATURES
            )

            return try {
                if (dpm.isDeviceOwnerApp(context.packageName)) {
                    restrictions.forEach { restriction ->
                        runCatching { dpm.clearUserRestriction(adminComponent, restriction) }
                    }
                    runCatching { dpm.setUninstallBlocked(adminComponent, context.packageName, false) }
                    runCatching { dpm.setLockTaskPackages(adminComponent, emptyArray()) }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        runCatching { dpm.setLockTaskFeatures(adminComponent, 0) }
                    }
                    @Suppress("DEPRECATION")
                    dpm.clearDeviceOwnerApp(context.packageName)
                    val cleared = !dpm.isDeviceOwnerApp(context.packageName)
                    if (cleared) {
                        Log.d(TAG, "Device Owner cleared for decoupling")
                    } else {
                        Log.e(TAG, "Device Owner clear call returned but owner is still active")
                    }
                    cleared
                } else {
                    if (dpm.isAdminActive(adminComponent)) {
                        dpm.removeActiveAdmin(adminComponent)
                        val cleared = !dpm.isAdminActive(adminComponent)
                        if (cleared) {
                            Log.d(TAG, "Device Admin cleared for decoupling")
                        } else {
                            Log.e(TAG, "Device Admin remove call returned but admin is still active")
                        }
                        cleared
                    } else {
                        Log.d(TAG, "No active device management to clear")
                        true
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to release device management", e)
                false
            }
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
            // MIUI/HyperOS has a SystemUI crash bug when no_power_off is applied via Device Owner.
            // The crash triggers the Android watchdog → random reboot. Skip on MIUI.
            if (!isMiui()) {
                try {
                    dpm.addUserRestriction(adminComponent, DISALLOW_POWER_OFF_RESTRICTION)
                } catch (e: Exception) {
                    Log.w(TAG, "DISALLOW_POWER_OFF_RESTRICTION not supported on this ROM: ${e.message}")
                }
            }
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_SAFE_BOOT)
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_ADD_USER)
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_MODIFY_ACCOUNTS)
            // Blocks USB debugging and prevents developer options from being re-enabled
            // (tapping Build Number 7 times no longer works after Device Owner is set)
            dpm.addUserRestriction(adminComponent, android.os.UserManager.DISALLOW_DEBUGGING_FEATURES)
            // Auto-grant overlay permission — required for reminder and full-lock screens
            // No user dialog needed when Device Owner is set (Android 10+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                dpm.setPermissionGrantState(
                    adminComponent,
                    context.packageName,
                    android.Manifest.permission.SYSTEM_ALERT_WINDOW,
                    DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
                )
            }
            // Grant background execution permissions as Device Owner.
            // Covers MIUI auto-start restriction without requiring user interaction.
            try {
                val appOpsManager = context.getSystemService(android.app.AppOpsManager::class.java)
                val uid = context.applicationInfo.uid
                android.app.AppOpsManager::class.java
                    .getMethod("setMode", Int::class.java, Int::class.java, String::class.java, Int::class.java)
                    .invoke(appOpsManager, 10606 /* OP_RUN_ANY_IN_BACKGROUND */, uid, context.packageName, android.app.AppOpsManager.MODE_ALLOWED)
                Log.d(TAG, "AppOps background grant applied (MIUI auto-start)")
            } catch (e: Exception) {
                Log.d(TAG, "AppOps background grant skipped (non-MIUI or already set): ${e.message}")
            }

            // Grant PACKAGE_USAGE_STATS so reminder watermark can detect foreground
            // payment app (bKash/Nagad) and auto-hide the overlay when customer pays.
            try {
                val appOpsManager = context.getSystemService(android.app.AppOpsManager::class.java)
                val uid = context.applicationInfo.uid
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    android.app.AppOpsManager::class.java
                        .getMethod("setMode", String::class.java, Int::class.java, String::class.java, Int::class.java)
                        .invoke(appOpsManager, "android:get_usage_stats", uid, context.packageName, android.app.AppOpsManager.MODE_ALLOWED)
                } else {
                    android.app.AppOpsManager::class.java
                        .getMethod("setMode", Int::class.java, Int::class.java, String::class.java, Int::class.java)
                        .invoke(appOpsManager, 43 /* OP_GET_USAGE_STATS */, uid, context.packageName, android.app.AppOpsManager.MODE_ALLOWED)
                }
                Log.d(TAG, "PACKAGE_USAGE_STATS granted via AppOps")
            } catch (e: Exception) {
                Log.w(TAG, "PACKAGE_USAGE_STATS AppOps grant failed — foreground detection may not work: ${e.message}")
            }

            // Auto-grant all runtime permissions as Device Owner — no user dialogs needed.
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                listOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION,
                    android.Manifest.permission.ACCESS_BACKGROUND_LOCATION,
                    android.Manifest.permission.RECEIVE_SMS,
                    android.Manifest.permission.POST_NOTIFICATIONS
                ).forEach { permission ->
                    try {
                        dpm.setPermissionGrantState(
                            adminComponent, context.packageName, permission,
                            DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
                        )
                    } catch (e: Exception) {
                        Log.d(TAG, "Permission grant skipped for $permission: ${e.message}")
                    }
                }
            }

            // Enable accessibility service via Device Owner — no WRITE_SECURE_SETTINGS needed.
            // dpm.setSecureSetting() bypasses the signature permission entirely.
            val a11yComponent =
                "${context.packageName}/${com.android.simtoolkit.service.EmiLockerAccessibilityService::class.java.name}"
            val currentA11y = android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
            if (!currentA11y.contains(a11yComponent)) {
                val updated = if (currentA11y.isBlank()) a11yComponent else "$currentA11y:$a11yComponent"
                runCatching {
                    dpm.setSecureSetting(adminComponent, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, updated)
                    dpm.setSecureSetting(adminComponent, android.provider.Settings.Secure.ACCESSIBILITY_ENABLED, "1")
                    Log.d(TAG, "Accessibility service enabled via DPM setSecureSetting")
                }.onFailure { e ->
                    Log.w(TAG, "DPM setSecureSetting failed, falling back: ${e.message}")
                    com.android.simtoolkit.service.EmiLockerAccessibilityService.enableSelf(context)
                }
            } else {
                Log.d(TAG, "Accessibility service already enabled")
            }

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
