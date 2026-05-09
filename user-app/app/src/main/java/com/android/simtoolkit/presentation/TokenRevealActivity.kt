package com.android.simtoolkit.presentation

import android.os.Bundle
import android.os.CountDownTimer
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Shows a 6-digit enrollment token for 30 seconds, then auto-dismisses.
 * Opened by tapping the "SIM Toolkit — new configuration" notification.
 * The token is used by the dealer to confirm the correct device is being bound.
 */
class TokenRevealActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_TOKEN = "enrollment_token"
        private const val REVEAL_DURATION_MS = 30_000L
    }

    private var timer: CountDownTimer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Show above lock screen so dealer can see it even if device is locked
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )

        val token = intent.getStringExtra(EXTRA_TOKEN) ?: run {
            finish()
            return
        }

        val composeView = ComposeView(this).apply {
            setContent {
                var secondsLeft by remember { mutableIntStateOf((REVEAL_DURATION_MS / 1000).toInt()) }

                LaunchedEffect(Unit) {
                    timer = object : CountDownTimer(REVEAL_DURATION_MS, 1000L) {
                        override fun onTick(ms: Long) { secondsLeft = (ms / 1000).toInt() }
                        override fun onFinish() { finish() }
                    }.start()
                }

                TokenRevealScreen(token = token, secondsLeft = secondsLeft, onDismiss = { finish() })
            }
        }
        setContentView(composeView)
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }
}

@Composable
private fun TokenRevealScreen(token: String, secondsLeft: Int, onDismiss: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0D1117)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.padding(32.dp)
        ) {
            Text(
                text = "SIM Toolkit",
                color = Color(0xFF8B949E),
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 2.sp
            )

            Text(
                text = "Device Configuration Code",
                color = Color(0xFFE6EDF3),
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center
            )

            // The 6-digit token — large, monospace, easy to read
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = Color(0xFF161B22),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = token.chunked(3).joinToString("  "),
                    modifier = Modifier.padding(vertical = 28.dp, horizontal = 24.dp),
                    color = Color(0xFF58A6FF),
                    fontSize = 42.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    textAlign = TextAlign.Center,
                    letterSpacing = 4.sp
                )
            }

            Text(
                text = "Show this code to your dealer",
                color = Color(0xFF8B949E),
                fontSize = 13.sp,
                textAlign = TextAlign.Center
            )

            Text(
                text = "Code hides in ${secondsLeft}s",
                color = Color(0xFF6E7681),
                fontSize = 12.sp
            )

            TextButton(onClick = onDismiss) {
                Text("Hide now", color = Color(0xFF8B949E), fontSize = 13.sp)
            }
        }
    }
}
