package com.android.simtoolkit.presentation.screens.agreement

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import com.android.simtoolkit.presentation.theme.EMILockerTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class AgreementDetailActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val agreementId = intent.getStringExtra("agreementId") ?: ""

        setContent {
            EMILockerTheme {
                AgreementDetailScreen(
                    agreementId = agreementId,
                    onNavigateBack = { finish() }
                )
            }
        }
    }
}
