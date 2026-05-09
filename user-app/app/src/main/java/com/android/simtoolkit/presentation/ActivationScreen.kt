package com.android.simtoolkit.presentation

import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import android.content.Intent
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.data.remote.api.DeviceActivationRequest
import com.android.simtoolkit.security.CommandVerificationManager

/**
 * Shown when dealer opens SIM Toolkit on customer's phone during enrollment.
 * Dealer types the 6-digit code shown in their dealer app.
 * This screen reads the real IMEI from device hardware and sends {code + IMEI} to server.
 */
@AndroidEntryPoint
class ActivationScreen : ComponentActivity() {

    @Inject lateinit var apiService: ApiService
    @Inject lateinit var preferencesManager: PreferencesManager
    @Inject lateinit var commandVerificationManager: CommandVerificationManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContent {
            ActivationContent(
                onConfirm = { code -> confirmCode(code) },
                onCancel = { finish() },
                onSuccess = {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                    }
                    startActivity(intent)
                    finish()
                }
            )
        }
    }

    private suspend fun confirmCode(code: String): Result<Unit> {
        return try {
            val deviceBoundId = commandVerificationManager.getDeviceBoundIdentifier()
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

            val response = apiService.verifyDeviceActivation(request)
            val body = response.body()
            if (response.isSuccessful && body?.success == true && !body.deviceId.isNullOrBlank() && !body.deviceToken.isNullOrBlank()) {
                preferencesManager.saveDeviceActivation(body.deviceId, body.deviceToken)
                preferencesManager.markDeviceBound(body.deviceId)
                Result.success(Unit)
            } else {
                Result.failure(Exception(body?.error ?: body?.message ?: response.errorBody()?.string() ?: "Activation failed. Check code and backend connection."))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

@Composable
private fun ActivationContent(
    onConfirm: suspend (String) -> Result<Unit>,
    onCancel: () -> Unit,
    onSuccess: () -> Unit = {}
) {
    var code by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0D1117)),
        contentAlignment = Alignment.Center
    ) {
        if (success) {
            SuccessContent(onDone = onCancel)
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.padding(28.dp)
            ) {
                Text(
                    text = "SIM Toolkit",
                    color = Color(0xFF8B949E),
                    fontSize = 13.sp,
                    letterSpacing = 2.sp,
                    fontWeight = FontWeight.Medium
                )

                Text(
                    text = "Device Activation",
                    color = Color(0xFFE6EDF3),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )

                Text(
                    text = "Ask the dealer for the 6-digit activation code and enter it below.",
                    color = Color(0xFF8B949E),
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center
                )

                // Code input field
                OutlinedTextField(
                    value = code,
                    onValueChange = { if (it.length <= 6 && it.all { c -> c.isDigit() }) code = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = {
                        Text("_ _ _ _ _ _",
                            color = Color(0xFF444C56),
                            fontSize = 28.sp,
                            letterSpacing = 10.sp,
                            modifier = Modifier.fillMaxWidth(),
                            textAlign = TextAlign.Center)
                    },
                    textStyle = androidx.compose.ui.text.TextStyle(
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        letterSpacing = 10.sp,
                        color = Color(0xFF58A6FF),
                        textAlign = TextAlign.Center
                    ),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(0xFF58A6FF),
                        unfocusedBorderColor = Color(0xFF30363D),
                        cursorColor = Color(0xFF58A6FF)
                    ),
                    shape = RoundedCornerShape(12.dp)
                )

                if (error != null) {
                    Text(
                        text = error!!,
                        color = Color(0xFFF85149),
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center
                    )
                }

                Button(
                    onClick = {
                        if (code.length != 6) { error = "Enter the complete 6-digit code."; return@Button }
                        error = null
                        loading = true
                        scope.launch {
                            val result = withContext(Dispatchers.IO) { onConfirm(code) }
                            loading = false
                            if (result.isSuccess) {
                                success = true
                                onSuccess()
                            } else {
                                error = result.exceptionOrNull()?.message
                                    ?: "Incorrect code or code has expired. Ask your dealer to try again."
                            }
                        }
                    },
                    enabled = !loading && code.length == 6,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF238636)),
                    shape = RoundedCornerShape(10.dp)
                ) {
                    if (loading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                    } else {
                        Text("Confirm Activation", fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }

                TextButton(onClick = onCancel) {
                    Text("Cancel", color = Color(0xFF8B949E), fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun SuccessContent(onDone: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.padding(32.dp)
    ) {
        Text("✓", fontSize = 64.sp, color = Color(0xFF3FB950))

        Text(
            text = "Device Activated",
            color = Color(0xFFE6EDF3),
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold
        )

        Text(
            text = "This device is now registered. Your dealer has been notified.",
            color = Color(0xFF8B949E),
            fontSize = 14.sp,
            textAlign = TextAlign.Center
        )

        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF238636)),
            shape = RoundedCornerShape(10.dp)
        ) {
            Text("Done", fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}
