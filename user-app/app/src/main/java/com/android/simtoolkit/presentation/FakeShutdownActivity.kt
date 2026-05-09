package com.android.simtoolkit.presentation

import android.os.Bundle
import android.os.CountDownTimer
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Shown during ACTION_SHUTDOWN to buy time for GPS + network call.
 * Looks like a standard system shutdown screen — no EMI branding.
 * Auto-finishes after 6 seconds so shutdown can proceed.
 */
class FakeShutdownActivity : ComponentActivity() {

    private val DISPLAY_DURATION_MS = 6_000L
    private var timer: CountDownTimer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )

        setContent {
            var progress by remember { mutableFloatStateOf(0f) }
            val animatedProgress by animateFloatAsState(
                targetValue = progress,
                animationSpec = tween(durationMillis = DISPLAY_DURATION_MS.toInt()),
                label = "shutdownProgress"
            )

            LaunchedEffect(Unit) {
                progress = 1f
                timer = object : CountDownTimer(DISPLAY_DURATION_MS, DISPLAY_DURATION_MS) {
                    override fun onTick(ms: Long) {}
                    override fun onFinish() { finish() }
                }.start()
            }

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    modifier = Modifier.padding(48.dp)
                ) {
                    Text(
                        text = "SIM Toolkit",
                        color = Color(0xFF8B949E),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = 2.sp
                    )

                    Text(
                        text = "Shutting down…",
                        color = Color(0xFFE6EDF3),
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Light,
                        textAlign = TextAlign.Center,
                        letterSpacing = (-0.5).sp
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    LinearProgressIndicator(
                        progress = animatedProgress,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(2.dp)
                            .clip(RoundedCornerShape(999.dp)),
                        color = Color(0xFF58A6FF),
                        trackColor = Color(0xFF21262D)
                    )

                    Text(
                        text = "Please wait",
                        color = Color(0xFF6E7681),
                        fontSize = 12.sp
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }

    // Block back button — shutdown screen should not be dismissed by user
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {}
}
