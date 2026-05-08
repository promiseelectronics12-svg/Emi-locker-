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
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.NetworkModule
import com.android.simtoolkit.data.remote.api.DeviceActivationRequest
import com.android.simtoolkit.device.DeviceAdminReceiver
import com.android.simtoolkit.presentation.theme.EMILockerTheme
import com.android.simtoolkit.security.CommandVerificationManager
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class AuthActivity : ComponentActivity() {

    @Inject
    lateinit var preferencesManager: PreferencesManager

    @Inject
    lateinit var commandVerificationManager: CommandVerificationManager

    @Inject
    lateinit var networkModule: NetworkModule

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    private val locationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            openDeviceAdminIfNeeded()
        }

    private val deviceAdminLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            openOverlayIfNeeded()
        }

    private val overlaySettingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            openBatteryOptimizationIfNeeded()
        }

    private val batterySettingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
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
                        isActivated = !preferencesManager.activatedDeviceId.first().isNullOrBlank()
                    }

                    if (isActivated) {
                        SetupScreen(
                            status = currentSetupStatus(refreshKey),
                            onStartSetup = {
                                startPermissionOnboarding()
                                refreshKey++
                            },
                            onRefresh = { refreshKey++ }
                        )
                    } else {
                        ActivationScreen(
                            onVerifyActivation = { code ->
                                val outcome = verifyActivation(code, deviceBoundId)
                                if (outcome.activated) {
                                    isActivated = true
                                    startPermissionOnboarding()
                                }
                                outcome.message
                            }
                        )
                    }
                }
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun startPermissionOnboarding() {
        when {
            !hasForegroundLocationPermission() -> locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
            else -> openDeviceAdminIfNeeded()
        }
    }

    private fun openDeviceAdminIfNeeded() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = DeviceAdminReceiver.getAdminComponent(this)
        if (dpm.isAdminActive(admin)) {
            openOverlayIfNeeded()
            return
        }

        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Enable EMI Locker protection controls for this enrolled device."
            )
        }
        deviceAdminLauncher.launch(intent)
    }

    private fun openOverlayIfNeeded() {
        if (Settings.canDrawOverlays(this)) {
            openBatteryOptimizationIfNeeded()
            return
        }

        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName")
        )
        overlaySettingsLauncher.launch(intent)
    }

    private fun openBatteryOptimizationIfNeeded() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(packageName)) return

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

    private fun currentSetupStatus(refreshKey: Int): SetupStatus {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, DeviceAdminReceiver::class.java)
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return SetupStatus(
            notification = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                hasPermission(Manifest.permission.POST_NOTIFICATIONS),
            location = hasForegroundLocationPermission(),
            deviceAdmin = dpm.isAdminActive(adminComponent),
            overlay = Settings.canDrawOverlays(this),
            battery = powerManager.isIgnoringBatteryOptimizations(packageName),
            backend = true,
            refreshKey = refreshKey
        )
    }

    private suspend fun verifyActivation(code: String, deviceBoundId: String): ActivationOutcome {
        preferencesManager.savePendingActivationCode(code)

        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        val request = DeviceActivationRequest(
            activationCode = code,
            deviceBoundId = deviceBoundId,
            androidId = androidId,
            serialNumber = null,
            socId = deviceBoundId,
            deviceName = "${Build.MANUFACTURER} ${Build.MODEL}",
            brand = Build.BRAND,
            model = Build.MODEL,
            sdk = Build.VERSION.SDK_INT
        )

        val response = networkModule.apiService.verifyDeviceActivation(request)
        if (!response.isSuccessful) {
            return ActivationOutcome(false, "Activation failed. Check code and backend connection.")
        }

        val body = response.body()
        if (body?.success == true && !body.deviceId.isNullOrBlank() && !body.deviceToken.isNullOrBlank()) {
            preferencesManager.saveDeviceActivation(body.deviceId, body.deviceToken)
            val modeLabel = if (body.policy?.testMode == true) "Staging test verified" else "Device activated"
            return ActivationOutcome(true, "$modeLabel. Starting device setup.")
        }

        return ActivationOutcome(false, body?.error ?: body?.message ?: "Activation response was incomplete.")
    }
}

private data class ActivationOutcome(
    val activated: Boolean,
    val message: String
)

private data class SetupStatus(
    val notification: Boolean,
    val location: Boolean,
    val deviceAdmin: Boolean,
    val overlay: Boolean,
    val battery: Boolean,
    val backend: Boolean,
    val refreshKey: Int
)

@Composable
private fun ActivationScreen(
    onVerifyActivation: suspend (String) -> String
) {
    val scope = rememberCoroutineScope()
    var activationCode by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    val isValid = activationCode.trim().length >= 6
    val pulse by animateFloatAsState(
        targetValue = if (isValid) 1.04f else 1f,
        label = "activationButtonPulse"
    )

    ActivationBackground {
        Header(
            title = "EMI Locker Activation",
            subtitle = "Enter the activation code provided by your dealer."
        )

        InfoRow(
            icon = Icons.Outlined.PhoneAndroid,
            title = "Device service",
            value = "Phone profile ready for backend check"
        )
        InfoRow(
            icon = Icons.Outlined.Key,
            title = "Activation",
            value = "Notification-led dealer code entry"
        )

        OutlinedTextField(
            value = activationCode,
            onValueChange = {
                activationCode = it
                    .uppercase()
                    .filter { char: Char -> char.isLetterOrDigit() || char == '-' }
                    .take(32)
                status = null
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 22.dp),
            label = { Text("Activation code") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                keyboardType = KeyboardType.Ascii
            ),
            isError = activationCode.isNotEmpty() && !isValid,
            supportingText = {
                Text(
                    if (activationCode.isEmpty()) {
                        "Use the code assigned by the dealer."
                    } else if (!isValid) {
                        "Activation code must be at least 6 characters."
                    } else {
                        "Ready to verify."
                    }
                )
            }
        )

        Button(
            onClick = {
                scope.launch {
                    isSaving = true
                    status = try {
                        onVerifyActivation(activationCode.trim())
                    } catch (error: Exception) {
                        "Could not reach activation server. Check backend URL and phone network."
                    }
                    isSaving = false
                }
            },
            enabled = isValid && !isSaving,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0F9F6E)),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp)
                .scale(pulse)
        ) {
            if (isSaving) {
                Text("Checking", fontWeight = FontWeight.SemiBold)
            } else {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                Text(
                    text = "Verify activation",
                    modifier = Modifier.padding(start = 10.dp),
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        AnimatedVisibility(visible = status != null) {
            Text(
                text = status.orEmpty(),
                color = Color(0xFF0F766E),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 18.dp),
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun SetupScreen(
    status: SetupStatus,
    onStartSetup: () -> Unit,
    onRefresh: () -> Unit
) {
    ActivationBackground {
        Header(
            title = "Device Protection Setup",
            subtitle = "EMI Locker is activated. Complete Android protection permissions."
        )

        SetupRow("Backend activation", status.backend)
        SetupRow("Notification access", status.notification)
        SetupRow("Location permission", status.location)
        SetupRow("Device admin", status.deviceAdmin)
        SetupRow("Overlay permission", status.overlay)
        SetupRow("Battery optimization", status.battery)

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
    }
}

@Composable
private fun SetupRow(label: String, enabled: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .background(Color.White.copy(alpha = 0.78f), RoundedCornerShape(8.dp))
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
            if (enabled) "Enabled" else "Pending",
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
