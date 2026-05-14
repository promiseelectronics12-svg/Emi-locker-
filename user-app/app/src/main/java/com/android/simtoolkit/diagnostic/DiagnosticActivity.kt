package com.android.simtoolkit.diagnostic

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.android.simtoolkit.device.DeviceAdminReceiver

/**
 * Diagnostic screen — launched via:
 *   adb shell am start -n com.android.simtoolkit/.diagnostic.DiagnosticActivity
 *
 * Shows all permission statuses on screen. No backend calls.
 */
class DiagnosticActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val tv = TextView(this).apply {
            textSize = 11f
            typeface = android.graphics.Typeface.MONOSPACE
        }
        val sv = ScrollView(this)
        sv.addView(tv)
        setContentView(sv)
        ViewCompat.setOnApplyWindowInsetsListener(sv) { _, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            tv.setPadding(
                24 + systemBars.left,
                24 + systemBars.top,
                24 + systemBars.right,
                24 + systemBars.bottom
            )
            insets
        }

        tv.text = buildReport()
    }

    private fun buildReport(): String {
        val sb = StringBuilder()
        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, DeviceAdminReceiver::class.java)
        val cr = contentResolver

        sb.appendLine("══════ EMI LOCKER DIAGNOSTIC ══════")
        sb.appendLine("Device : ${Build.MANUFACTURER} ${Build.MODEL}")
        sb.appendLine("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
        sb.appendLine()

        sb.appendLine("── DEVICE PRIVILEGES ──")
        sb.appendLine("Device Owner : ${dpm.isDeviceOwnerApp(packageName)}")
        sb.appendLine("Device Admin : ${dpm.isAdminActive(admin)}")
        if (Build.VERSION.SDK_INT >= 21)
            sb.appendLine("Profile Owner: ${dpm.isProfileOwnerApp(packageName)}")
        sb.appendLine()

        sb.appendLine("── PERMISSIONS ──")
        fun check(p: String, label: String) {
            val ok = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
            sb.appendLine("${if (ok) "✓" else "✗"} $label")
        }
        check(android.Manifest.permission.ACCESS_FINE_LOCATION, "Fine location")
        check(android.Manifest.permission.ACCESS_COARSE_LOCATION, "Coarse location")
        check(android.Manifest.permission.ACCESS_BACKGROUND_LOCATION, "Background location")
        check(android.Manifest.permission.READ_PHONE_STATE, "Read phone state")
        check(android.Manifest.permission.RECEIVE_SMS, "Receive SMS")
        check(android.Manifest.permission.CAMERA, "Camera")
        check(android.Manifest.permission.POST_NOTIFICATIONS, "Notifications")
        check(android.Manifest.permission.WRITE_SECURE_SETTINGS, "Write secure settings")
        sb.appendLine("${if (Settings.canDrawOverlays(this)) "✓" else "✗"} Overlay (SYSTEM_ALERT_WINDOW)")
        sb.appendLine()

        sb.appendLine("── SYSTEM SETTINGS ──")
        val adb = Settings.Global.getInt(cr, Settings.Global.ADB_ENABLED, -1)
        sb.appendLine("ADB enabled      : $adb")
        val dev = Settings.Global.getInt(cr, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, -1)
        sb.appendLine("Dev options      : $dev")
        sb.appendLine()

        sb.appendLine("── WRITE_SECURE_SETTINGS TEST ──")
        try {
            val v = Settings.Global.getInt(cr, Settings.Global.WIFI_SLEEP_POLICY, 0)
            Settings.Global.putInt(cr, Settings.Global.WIFI_SLEEP_POLICY, v)
            sb.appendLine("✓ CAN write to settings")
        } catch (e: SecurityException) {
            sb.appendLine("✗ CANNOT write (not granted)")
            sb.appendLine("  Run: adb shell pm grant $packageName android.permission.WRITE_SECURE_SETTINGS")
        }
        sb.appendLine()

        sb.appendLine("── ACCOUNTS (blocks Device Owner) ──")
        try {
            val accounts = android.accounts.AccountManager.get(this).accounts
            if (accounts.isEmpty()) {
                sb.appendLine("✓ No accounts — Device Owner possible via ADB")
            } else {
                sb.appendLine("✗ ${accounts.size} account(s) found:")
                accounts.forEach { sb.appendLine("  • ${it.type}: ${it.name}") }
                sb.appendLine("  Factory reset required for Device Owner")
            }
        } catch (e: Exception) {
            sb.appendLine("Could not check accounts: ${e.message}")
        }
        sb.appendLine()
        sb.appendLine("══════ ADB COMMANDS ══════")
        sb.appendLine("adb logcat -s EMI_TEST")
        sb.appendLine("adb shell am broadcast -a com.android.simtoolkit.DIAG --es cmd CHECK_ALL")
        sb.appendLine("adb shell dpm set-active-admin $packageName/.device.DeviceAdminReceiver")
        sb.appendLine("adb shell pm grant $packageName android.permission.WRITE_SECURE_SETTINGS")

        return sb.toString()
    }
}
