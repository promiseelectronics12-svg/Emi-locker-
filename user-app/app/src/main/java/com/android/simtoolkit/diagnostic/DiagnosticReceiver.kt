package com.android.simtoolkit.diagnostic

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.device.DeviceAdminReceiver
import com.android.simtoolkit.service.EmiLockerService

/**
 * ADB-accessible diagnostic receiver.
 *
 * Usage from PC:
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd CHECK_ALL
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd CHECK_PERMISSIONS
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd CHECK_DEVICE_OWNER
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd CHECK_SETTINGS
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd DISABLE_ADB
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd DISABLE_DEV_OPTIONS
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd TEST_PARTIAL_LOCK
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd TEST_UNLOCK
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd TEST_LOCATION --es pullId adb_test
 *   adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd PING
 *
 * Read results:
 *   adb logcat -s EMI_TEST
 */
class DiagnosticReceiver : BroadcastReceiver() {

    companion object {
        const val TAG = "EMI_TEST"
        const val ACTION = "com.android.simtoolkit.DIAG"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val cmd = intent.getStringExtra("cmd")?.uppercase() ?: "PING"
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log("CMD: $cmd")

        when (cmd) {
            "PING"              -> handlePing(context)
            "CHECK_ALL"         -> { handlePermissions(context); handleDeviceOwner(context); handleSettings(context) }
            "CHECK_PERMISSIONS" -> handlePermissions(context)
            "CHECK_DEVICE_OWNER"-> handleDeviceOwner(context)
            "CHECK_SETTINGS"    -> handleSettings(context)
            "DISABLE_ADB"       -> handleDisableAdb(context)
            "DISABLE_DEV_OPTIONS" -> handleDisableDevOptions(context)
            "OPEN_DIAGNOSTIC"   -> openDiagnosticScreen(context)
            "TEST_PARTIAL_LOCK"  -> handleTestLockCommand(context, EmiLockerService.ACTION_PARTIAL_LOCK)
            "TEST_FULL_LOCK"     -> handleTestLockCommand(context, EmiLockerService.ACTION_LOCK_DEVICE)
            "TEST_UNLOCK"        -> handleTestLockCommand(context, EmiLockerService.ACTION_UNLOCK)
            "TEST_LOCATION"     -> handleTestLocation(context, intent)
            else -> log("UNKNOWN CMD: $cmd")
        }
        log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    private fun handlePing(ctx: Context) {
        log("PONG — app is alive")
        log("Package: ${ctx.packageName}")
        log("Android SDK: ${Build.VERSION.SDK_INT} (Android ${Build.VERSION.RELEASE})")
        log("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
    }

    private fun handlePermissions(ctx: Context) {
        log("─── PERMISSIONS ───")
        val perms = listOf(
            android.Manifest.permission.ACCESS_FINE_LOCATION        to "ACCESS_FINE_LOCATION",
            android.Manifest.permission.ACCESS_COARSE_LOCATION      to "ACCESS_COARSE_LOCATION",
            android.Manifest.permission.ACCESS_BACKGROUND_LOCATION  to "ACCESS_BACKGROUND_LOCATION",
            android.Manifest.permission.READ_PHONE_STATE             to "READ_PHONE_STATE",
            android.Manifest.permission.RECEIVE_SMS                  to "RECEIVE_SMS",
            android.Manifest.permission.CAMERA                      to "CAMERA",
            android.Manifest.permission.POST_NOTIFICATIONS          to "POST_NOTIFICATIONS",
            android.Manifest.permission.FOREGROUND_SERVICE          to "FOREGROUND_SERVICE",
            android.Manifest.permission.RECEIVE_BOOT_COMPLETED      to "RECEIVE_BOOT_COMPLETED",
            android.Manifest.permission.WRITE_SECURE_SETTINGS       to "WRITE_SECURE_SETTINGS",
        )
        for ((perm, name) in perms) {
            val granted = ctx.checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
            log("  ${if (granted) "✓" else "✗"} $name")
        }

        val overlayOk = Settings.canDrawOverlays(ctx)
        log("  ${if (overlayOk) "✓" else "✗"} SYSTEM_ALERT_WINDOW (overlay)")

        val accessibilityOk = isAccessibilityEnabled(ctx)
        log("  ${if (accessibilityOk) "✓" else "✗"} ACCESSIBILITY_SERVICE")

        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(ctx, DeviceAdminReceiver::class.java)
        val isAdmin = dpm.isAdminActive(admin)
        log("  ${if (isAdmin) "✓" else "✗"} DEVICE_ADMIN")
    }

    private fun handleDeviceOwner(ctx: Context) {
        log("─── DEVICE OWNER / ADMIN ───")
        val dpm = ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(ctx, DeviceAdminReceiver::class.java)

        val isOwner  = dpm.isDeviceOwnerApp(ctx.packageName)
        val isAdmin  = dpm.isAdminActive(admin)
        val isProfile = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
            dpm.isProfileOwnerApp(ctx.packageName) else false

        log("  Device Owner  : $isOwner")
        log("  Device Admin  : $isAdmin")
        log("  Profile Owner : $isProfile")

        if (isOwner) {
            log("  ★ FULL CONTROL — Device Owner active")
            try {
                val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as android.telephony.TelephonyManager
                @Suppress("DEPRECATION")
                val imei = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) tm.imei else tm.deviceId
                log("  IMEI via TM   : $imei")
            } catch (e: Exception) {
                log("  IMEI via TM   : FAILED (${e.message})")
            }
        } else if (isAdmin) {
            log("  ★ PARTIAL — Device Admin only. Cannot get IMEI or hide from settings.")
        } else {
            log("  ✗ NO PRIVILEGE — app has neither Device Admin nor Device Owner")
            log("  ▶ Run: adb shell dpm set-active-admin com.android.simtoolkit/.device.DeviceAdminReceiver")
        }

        // Try device owner grant attempt info
        try {
            val accounts = android.accounts.AccountManager.get(ctx).accounts
            if (accounts.isNotEmpty()) {
                log("  ⚠ Device Owner blocked — ${accounts.size} Google/system account(s) on device")
                log("    Must factory reset to grant Device Owner")
            } else {
                log("  ℹ No accounts found — Device Owner may be grantable via ADB")
                log("  ▶ Run: adb shell dpm set-device-owner com.android.simtoolkit/.device.DeviceAdminReceiver")
            }
        } catch (e: Exception) {
            log("  Account check failed: ${e.message}")
        }
    }

    private fun handleSettings(ctx: Context) {
        log("─── CURRENT SYSTEM SETTINGS ───")
        val cr = ctx.contentResolver

        val adbEnabled = Settings.Global.getInt(cr, Settings.Global.ADB_ENABLED, -1)
        log("  ADB enabled       : ${adbEnabled == 1}")

        val devOptions = Settings.Global.getInt(cr, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, -1)
        log("  Dev options on    : ${devOptions == 1}")

        @Suppress("DEPRECATION")
        val locationMode = Settings.Secure.getInt(cr, Settings.Secure.LOCATION_MODE, -1)
        log("  Location mode     : $locationMode (3=high accuracy)")

        val lockTimeout = Settings.Secure.getLong(cr, "lock_screen_lock_after_timeout", -1L)
        log("  Lock timeout (ms) : $lockTimeout")

        val installerUnknown = Settings.Secure.getInt(cr, Settings.Secure.INSTALL_NON_MARKET_APPS, -1)
        log("  Install unknown   : ${installerUnknown == 1}")

        // Test WRITE_SECURE_SETTINGS by trying a benign write
        try {
            val current = Settings.Global.getInt(cr, Settings.Global.WIFI_SLEEP_POLICY, 0)
            Settings.Global.putInt(cr, Settings.Global.WIFI_SLEEP_POLICY, current)
            log("  WRITE_SECURE_SETTINGS: ✓ WORKS (can write to settings)")
        } catch (e: SecurityException) {
            log("  WRITE_SECURE_SETTINGS: ✗ NOT granted")
            log("  ▶ Run: adb shell pm grant com.android.simtoolkit android.permission.WRITE_SECURE_SETTINGS")
        }
    }

    private fun handleTestLocation(ctx: Context, intent: Intent) {
        log("─── TEST LOCATION ───")
        if (!BuildConfig.DEBUG) {
            log("  Refusing TEST_LOCATION in non-debug build")
            return
        }

        val pullId = intent.getStringExtra("pullId") ?: "adb_test_${System.currentTimeMillis()}"
        val serviceIntent = Intent(ctx, EmiLockerService::class.java).apply {
            action = EmiLockerService.ACTION_REPORT_LOCATION
            putExtra(EmiLockerService.EXTRA_PULL_ID, pullId)
        }

        try {
            ctx.startForegroundService(serviceIntent)
            log("  Started location foreground service with pullId=$pullId")
        } catch (e: Exception) {
            log("  Failed to start location service: ${e.message}")
        }
    }

    private fun handleTestLockCommand(ctx: Context, action: String) {
        log("--- TEST LOCK COMMAND ---")
        if (!BuildConfig.DEBUG) {
            log("  Refusing lock test command in non-debug build")
            return
        }

        val serviceIntent = Intent(ctx, EmiLockerService::class.java).apply {
            this.action = action
        }

        try {
            ctx.startForegroundService(serviceIntent)
            log("  Started EmiLockerService with action=$action")
        } catch (e: Exception) {
            log("  Failed to start lock service: ${e.message}")
        }
    }

    private fun handleDisableAdb(ctx: Context) {
        log("─── DISABLE ADB ───")
        try {
            Settings.Global.putInt(ctx.contentResolver, Settings.Global.ADB_ENABLED, 0)
            val verify = Settings.Global.getInt(ctx.contentResolver, Settings.Global.ADB_ENABLED, -1)
            log("  ADB_ENABLED set to 0. Current value: $verify")
            log("  ${if (verify == 0) "✓ ADB DISABLED successfully" else "✗ Failed to disable ADB"}")
        } catch (e: SecurityException) {
            log("  ✗ FAILED — WRITE_SECURE_SETTINGS not granted")
            log("  ▶ Run: adb shell pm grant com.android.simtoolkit android.permission.WRITE_SECURE_SETTINGS")
        }
    }

    private fun handleDisableDevOptions(ctx: Context) {
        log("─── DISABLE DEVELOPER OPTIONS ───")
        try {
            Settings.Global.putInt(ctx.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0)
            val verify = Settings.Global.getInt(ctx.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, -1)
            log("  DEV_OPTIONS set to 0. Current value: $verify")
            log("  ${if (verify == 0) "✓ DEVELOPER OPTIONS DISABLED successfully" else "✗ Failed to disable dev options"}")
        } catch (e: SecurityException) {
            log("  ✗ FAILED — WRITE_SECURE_SETTINGS not granted")
        }
    }

    private fun openDiagnosticScreen(ctx: Context) {
        val i = Intent(ctx, DiagnosticActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        ctx.startActivity(i)
        log("DiagnosticActivity launched")
    }

    private fun isAccessibilityEnabled(ctx: Context): Boolean {
        return try {
            val enabled = Settings.Secure.getString(
                ctx.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
            enabled.contains(ctx.packageName, ignoreCase = true)
        } catch (e: Exception) { false }
    }

    private fun log(msg: String) = Log.i(TAG, msg)
}
