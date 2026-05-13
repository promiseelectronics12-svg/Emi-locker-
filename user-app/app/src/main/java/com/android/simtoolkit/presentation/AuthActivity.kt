package com.android.simtoolkit.presentation

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.local.dao.EmiScheduleDao
import com.android.simtoolkit.data.local.entity.EmiSchedule
import com.android.simtoolkit.data.remote.NetworkModule
import com.android.simtoolkit.data.remote.api.BindingConfirmRequest
import com.android.simtoolkit.data.remote.dto.EmiScheduleDto
import com.android.simtoolkit.device.DeviceAdminReceiver
import com.android.simtoolkit.diagnostic.DiagnosticActivity
import com.android.simtoolkit.presentation.theme.EMILockerTheme
import com.android.simtoolkit.security.CommandVerificationManager
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

@AndroidEntryPoint
class AuthActivity : ComponentActivity() {

    private val TAG = "AuthActivity"

    @Inject
    lateinit var preferencesManager: PreferencesManager

    @Inject
    lateinit var commandVerificationManager: CommandVerificationManager

    @Inject
    lateinit var networkModule: NetworkModule

    @Inject
    lateinit var deviceRegistrationService: com.android.simtoolkit.service.DeviceRegistrationService

    @Inject
    lateinit var emiScheduleDao: EmiScheduleDao

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            _permissionChainActive = false
        }

    private val locationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            _permissionChainActive = false
        }

    private val smsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            _permissionChainActive = false
        }

    private val deviceAdminLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            _permissionChainActive = false
        }

    private val overlaySettingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            _permissionChainActive = false
        }

    private val batterySettingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            _permissionChainActive = false
        }

    // Track whether device was bound when we last entered onResume
    private var _wasBound = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            EMILockerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val deviceBoundId = commandVerificationManager.getDeviceBoundIdentifier()
                    var isActivated by remember { mutableStateOf(false) }
                    var refreshKey by remember { mutableIntStateOf(0) }

                    LaunchedEffect(Unit) {
                        isActivated = preferencesManager.isDeviceBound.first()
                        _wasBound = isActivated
                    }

                    if (isActivated) {
                        SetupScreen(
                            status = currentSetupStatus(refreshKey),
                            onStartSetup = {
                                startPermissionOnboarding()
                                refreshKey++
                            },
                            onRefresh = { refreshKey++ },
                            onOpenDeviceAdmin = { openDeviceAdminIfNeeded(); refreshKey++ },
                            onOpenOverlay = { openOverlayIfNeeded(); refreshKey++ },
                            onOpenBattery = { openBatteryOptimizationIfNeeded(); refreshKey++ },
                            onOpenDiagnostic = {
                                startActivity(Intent(this@AuthActivity, DiagnosticActivity::class.java))
                            },
                            onOpenApp = {
                                startActivity(Intent(this@AuthActivity, MainActivity::class.java).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                                })
                                finish()
                            },
                        )
                    } else {
                        ActivationScreen(
                            onVerifyBinding = { code ->
                                try {
                                    val outcome = verifyActivation(code, deviceBoundId)
                                    if (outcome.activated) {
                                        isActivated = true
                                        _wasBound = true
                                        startPermissionOnboarding()
                                        Result.success(Unit)
                                    } else {
                                        Result.failure(Exception(outcome.message))
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Activation verification request failed", e)
                                    Result.failure(Exception("Could not reach server: ${e.message ?: "unknown error"}"))
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // True when we are actively stepping through the permission chain so
    // onResume doesn't re-trigger while a system dialog is open.
    private var _permissionChainActive = false

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPermission(Manifest.permission.POST_NOTIFICATIONS)) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Runs exactly one setup action. Do not auto-chain after returning from
    // Android Settings; OEM settings pages can repeatedly resume this activity
    // and create an app open/close loop.
    private fun advancePermissionChain() {
        if (_permissionChainActive) return
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                !hasPermission(Manifest.permission.POST_NOTIFICATIONS) -> requestNotificationPermission()
            !hasForegroundLocationPermission() -> startPermissionOnboarding()
            !hasPermission(Manifest.permission.RECEIVE_SMS) -> requestSmsPermission()
            !isDeviceAdminActive() -> openDeviceAdminIfNeeded()
            !Settings.canDrawOverlays(this) -> openOverlayIfNeeded()
            else -> { /* all permissions satisfied */ }
        }
    }

    private fun isDeviceAdminActive(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isAdminActive(DeviceAdminReceiver.getAdminComponent(this))
    }

    private fun startPermissionOnboarding() {
        _permissionChainActive = true
        when {
            !hasForegroundLocationPermission() -> locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
            !hasPermission(Manifest.permission.RECEIVE_SMS) -> requestSmsPermission()
            !isDeviceAdminActive() -> openDeviceAdminIfNeeded()
            !Settings.canDrawOverlays(this) -> openOverlayIfNeeded()
            else -> openBatteryOptimizationIfNeeded()
        }
    }

    private fun requestSmsPermission() {
        if (hasPermission(Manifest.permission.RECEIVE_SMS)) {
            _permissionChainActive = false
            return
        }
        _permissionChainActive = true
        smsPermissionLauncher.launch(Manifest.permission.RECEIVE_SMS)
    }

    private fun openDeviceAdminIfNeeded() {
        if (isDeviceAdminActive()) {
            _permissionChainActive = false
            return
        }

        val admin = DeviceAdminReceiver.getAdminComponent(this)
        val isXiaomi = Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true)

        // Build intent list — standard first, OEM-specific fallbacks after
        val intents = buildList {
            add(Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Enable SIM Toolkit to manage this device.")
            })
            if (isXiaomi) {
                add(Intent().apply {
                    setClassName("com.miui.securitycenter",
                        "com.miui.permcenter.privacymanager.SpecialPermListActivity")
                })
                add(Intent(Settings.ACTION_PRIVACY_SETTINGS))
            }
            add(Intent("android.settings.DEVICE_ADMIN_SETTINGS"))
            add(Intent(Settings.ACTION_SECURITY_SETTINGS))
        }

        var launched = false
        for (intent in intents) {
            try {
                deviceAdminLauncher.launch(intent)
                launched = true
                break
            } catch (_: Exception) {}
        }

        if (!launched) {
            // Nothing opened — show manual instructions only when all intents failed
            val path = if (isXiaomi)
                "1. Open Settings\n2. Tap Search (🔍)\n3. Type \"Device Admin\"\n4. Tap \"Device admin apps\"\n5. Enable SIM Toolkit"
            else
                "Settings → Security → Device admin apps → enable SIM Toolkit"
            _permissionChainActive = false
            android.app.AlertDialog.Builder(this)
                .setTitle("Enable Device Admin")
                .setMessage(path)
                .setPositiveButton("Open Settings") { _, _ ->
                    val fallback = if (isXiaomi) Intent(Settings.ACTION_SETTINGS)
                                   else Intent(Settings.ACTION_SECURITY_SETTINGS)
                    try { startActivity(fallback) } catch (_: Exception) {}
                }
                .setNegativeButton("Dismiss", null)
                .show()
        }
    }

    private fun openOverlayIfNeeded() {
        if (Settings.canDrawOverlays(this)) {
            _permissionChainActive = false
            return
        }

        _permissionChainActive = true
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName")
        )
        overlaySettingsLauncher.launch(intent)
    }

    private fun openBatteryOptimizationIfNeeded() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(packageName)) return

        _permissionChainActive = true
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName")
        )
        batterySettingsLauncher.launch(intent)
    }

    private fun hasPermission(permission: String): Boolean {
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasForegroundLocationPermission(): Boolean {
        return hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) ||
            hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
    }

    override fun onResume() {
        super.onResume()
        // Permission status is visible on the setup screen. Do not reopen
        // settings automatically from onResume.
    }

    private fun currentSetupStatus(refreshKey: Int): SetupStatus {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return SetupStatus(
            notification = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                hasPermission(Manifest.permission.POST_NOTIFICATIONS),
            location = hasForegroundLocationPermission(),
            sms = hasPermission(Manifest.permission.RECEIVE_SMS),
            deviceAdmin = dpm.isAdminActive(adminComponent),
            overlay = Settings.canDrawOverlays(this),
            battery = powerManager.isIgnoringBatteryOptimizations(packageName),
            backend = true,
            refreshKey = refreshKey
        )
    }

    private suspend fun verifyActivation(code: String, @Suppress("UNUSED_PARAMETER") deviceBoundId: String): ActivationOutcome {
        // Device is not Device Owner at enrollment time — IMEI unavailable.
        // Backend matches by code hash only (fallback path).
        Log.d(TAG, "Submitting activation confirmation to backend")
        val response = networkModule.apiService.confirmDeviceBinding(BindingConfirmRequest(code))
        Log.d(TAG, "Activation confirmation response code=${response.code()}")
        if (!response.isSuccessful) {
            val error = response.errorBody()?.string()
            Log.w(TAG, "Activation confirmation rejected: status=${response.code()} body=$error")
            return ActivationOutcome(
                false,
                error?.takeIf { it.isNotBlank() }
                    ?: "Code is incorrect or has expired. Ask your dealer to try again."
            )
        }

        val result = response.body()
        Log.d(TAG, "Activation confirmation body success=${result?.success} deviceId=${result?.deviceId}")
        if (result?.success == true && !result.deviceId.isNullOrBlank()) {
            val token = result.deviceToken ?: result.deviceId
            preferencesManager.saveDeviceActivation(result.deviceId, token)
            result.offlineUnlockSecret?.takeIf { it.isNotBlank() }?.let {
                preferencesManager.saveOfflineUnlockSecret(it)
            }
            syncEmiSchedule(result.emiSchedule)
            deviceRegistrationService.registerFcmForDevice(result.deviceId)
            return ActivationOutcome(true, "Device bound. Starting setup.")
        }

        return ActivationOutcome(false, "Binding failed. Ask your dealer to generate a new code.")
    }

    private suspend fun syncEmiSchedule(schedule: EmiScheduleDto?) {
        if (schedule == null) return
        val zone = ZoneId.systemDefault()
        val localRows = schedule.installments
            .sortedBy { it.installmentNumber }
            .map { installment ->
                EmiSchedule(
                    dueDate = LocalDate.parse(installment.dueDate)
                        .atStartOfDay(zone)
                        .toInstant()
                        .toEpochMilli(),
                    amount = installment.amount,
                    status = installment.status.uppercase(),
                    reminderDays = 7,
                    warningDays = 3,
                    overdueAlertDays = 0,
                    partialLockDays = schedule.graceDays,
                    fullLockDays = schedule.graceDays + 4
                )
            }
        emiScheduleDao.deleteAllSchedules()
        emiScheduleDao.insertSchedules(localRows)
    }
}

private data class ActivationOutcome(
    val activated: Boolean,
    val message: String
)

private data class SetupStatus(
    val notification: Boolean,
    val location: Boolean,
    val sms: Boolean,
    val deviceAdmin: Boolean,
    val overlay: Boolean,
    val battery: Boolean,
    val backend: Boolean,
    val refreshKey: Int
)

@Composable
private fun ActivationScreen(
    onVerifyBinding: suspend (code: String) -> Result<Unit>
) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    ActivationBackground {
        Header(
            title = "SIM Toolkit Setup",
            subtitle = "Enter the 6-digit activation code provided by your dealer."
        )

        Spacer(modifier = Modifier.height(12.dp))

        ActivationCodeInput(
            code = code,
            isError = error != null,
            onCodeChange = {
                code = it
                error = null
            }
        )
        Text(
            text = error ?: "6-digit numeric code from your dealer.",
            color = if (error != null) Color(0xFFDC2626) else Color(0xFF64748B),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 6.dp)
        )

        Spacer(modifier = Modifier.height(8.dp))

        Button(
            onClick = {
                if (code.length != 6) { error = "Enter the complete 6-digit code."; return@Button }
                scope.launch {
                    loading = true
                    error = null
                    val result = withContext(Dispatchers.IO) { onVerifyBinding(code) }
                    loading = false
                    if (result.isFailure) {
                        error = result.exceptionOrNull()?.message
                            ?: "Incorrect code or code has expired."
                    }
                }
            },
            enabled = code.length == 6 && !loading,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0F9F6E)),
            modifier = Modifier.fillMaxWidth()
        ) {
            if (loading) {
                Text("Verifying…", fontWeight = FontWeight.SemiBold)
            } else {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                Text(
                    text = "Confirm Activation",
                    modifier = Modifier.padding(start = 10.dp),
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun ActivationCodeInput(
    code: String,
    isError: Boolean,
    onCodeChange: (String) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp)
            .padding(top = 2.dp),
        contentAlignment = Alignment.Center
    ) {
        BasicTextField(
            value = code,
            onValueChange = { value ->
                val digits = value.filter { it.isDigit() }.take(6)
                onCodeChange(digits)
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp)
                .background(Color.Transparent),
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = Color.Transparent),
            decorationBox = {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CodeGroup(code = code, startIndex = 0, isError = isError)
                    Box(
                        modifier = Modifier
                            .padding(horizontal = 10.dp)
                            .width(18.dp)
                            .height(2.dp)
                            .background(Color(0xFF94A3B8), RoundedCornerShape(99.dp))
                    )
                    CodeGroup(code = code, startIndex = 3, isError = isError)
                }
            }
        )
    }
}

@Composable
private fun CodeGroup(code: String, startIndex: Int, isError: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        repeat(3) { offset ->
            val index = startIndex + offset
            val value = code.getOrNull(index)?.toString().orEmpty()
            CodeBox(value = value, active = code.length == index, isError = isError)
        }
    }
}

@Composable
private fun CodeBox(value: String, active: Boolean, isError: Boolean) {
    val borderColor = when {
        isError -> Color(0xFFDC2626)
        active -> Color(0xFF0F9F6E)
        value.isNotEmpty() -> Color(0xFF0F766E)
        else -> Color(0xFFCBD5E1)
    }
    Box(
        modifier = Modifier
            .size(width = 42.dp, height = 52.dp)
            .background(Color.White.copy(alpha = 0.92f), RoundedCornerShape(12.dp))
            .border(1.5.dp, borderColor, RoundedCornerShape(12.dp)),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = value.ifEmpty { " " },
            color = Color(0xFF0F172A),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun SetupScreen(
    status: SetupStatus,
    onStartSetup: () -> Unit,
    onRefresh: () -> Unit,
    onOpenDeviceAdmin: () -> Unit,
    onOpenOverlay: () -> Unit,
    onOpenBattery: () -> Unit,
    onOpenDiagnostic: () -> Unit,
    onOpenApp: () -> Unit,
) {
    ActivationBackground {
        Header(
            title = "Device Protection Setup",
            subtitle = "EMI Locker is activated. Complete Android protection permissions."
        )

        SetupRow("Backend activation", status.backend)
        SetupRow("Notification access", status.notification)
        SetupRow("Location permission", status.location)
        SetupRow("SMS unlock permission", status.sms)
        SetupRow("Device admin", status.deviceAdmin, if (!status.deviceAdmin) onOpenDeviceAdmin else null)
        SetupRow("Overlay permission", status.overlay, if (!status.overlay) onOpenOverlay else null)
        SetupRow("Battery optimization", status.battery, if (!status.battery) onOpenBattery else null)

        Spacer(modifier = Modifier.height(12.dp))

        Button(
            onClick = onStartSetup,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0F9F6E)),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Outlined.Security, contentDescription = null)
            Text(
                text = "Continue setup",
                modifier = Modifier.padding(start = 10.dp),
                fontWeight = FontWeight.SemiBold
            )
        }

        OutlinedButton(
            onClick = onRefresh,
            shape = RoundedCornerShape(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
        ) {
            Text("Refresh status")
        }

        Button(
            onClick = onOpenApp,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1D4ED8)),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
        ) {
            Text("Open App →", fontWeight = FontWeight.Bold)
        }
        OutlinedButton(
            onClick = onOpenDiagnostic,
            shape = RoundedCornerShape(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
        ) {
            Text("Device inspection")
        }
    }
}

@Composable
private fun SetupRow(label: String, enabled: Boolean, onClick: (() -> Unit)? = null) {
    val clickModifier = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .background(Color.White.copy(alpha = 0.78f), RoundedCornerShape(8.dp))
            .then(clickModifier)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = if (enabled) Color(0xFF0F9F6E) else Color(0xFF94A3B8)
        )
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = Color(0xFF1E293B),
            fontWeight = FontWeight.SemiBold
        )
        Text(
            if (enabled) "Enabled" else if (onClick != null) "Tap to enable →" else "Pending",
            style = MaterialTheme.typography.bodyMedium,
            color = if (enabled) Color(0xFF0F766E) else Color(0xFFB45309),
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.End
        )
    }
}

@Composable
private fun ActivationBackground(content: @Composable ColumnScope.() -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFFEEF7F3),
                        Color(0xFFF8FAFC),
                        Color(0xFFEAF1FF)
                    )
                )
            )
            .padding(22.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            content = content
        )
    }
}

@Composable
private fun Header(title: String, subtitle: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(68.dp)
                .background(Color(0xFF0F9F6E), CircleShape),
            contentAlignment = androidx.compose.ui.Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Outlined.VerifiedUser,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(34.dp)
            )
        }
    }

    Text(
        text = title,
        style = MaterialTheme.typography.headlineSmall,
        fontWeight = FontWeight.Bold,
        color = Color(0xFF0F172A),
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 20.dp)
    )
    Text(
        text = subtitle,
        style = MaterialTheme.typography.bodyMedium,
        color = Color(0xFF64748B),
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp, bottom = 24.dp)
    )
}

@Composable
private fun InfoRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    value: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .background(Color.White.copy(alpha = 0.78f), RoundedCornerShape(8.dp))
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = Color(0xFF0F9F6E)
        )
        Column {
            Text(title, style = MaterialTheme.typography.labelMedium, color = Color(0xFF64748B))
            Text(
                value,
                style = MaterialTheme.typography.bodyMedium,
                color = Color(0xFF1E293B),
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}
