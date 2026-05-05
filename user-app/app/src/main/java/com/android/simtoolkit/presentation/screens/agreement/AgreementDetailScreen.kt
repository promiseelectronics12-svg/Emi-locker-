package com.android.simtoolkit.presentation.screens.agreement

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.android.simtoolkit.data.remote.api.PaymentDto

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgreementDetailScreen(
    agreementId: String,
    onNavigateBack: () -> Unit,
    viewModel: AgreementDetailViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(agreementId) {
        viewModel.loadAgreement(agreementId)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Agreement Details") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        if (uiState.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else if (uiState.agreement != null) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text(
                                text = uiState.agreement!!.emiNumber,
                                style = MaterialTheme.typography.headlineSmall
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = "Total Amount: ৳${uiState.agreement!!.totalAmount}",
                                style = MaterialTheme.typography.bodyLarge
                            )
                            Text(
                                text = "Monthly Payment: ৳${uiState.agreement!!.monthlyPayment}",
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Text(
                                text = "Down Payment: ৳${uiState.agreement!!.downPayment}",
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Text(
                                text = "Tenure: ${uiState.agreement!!.tenureMonths} months",
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Row {
                                Surface(
                                    color = when (uiState.agreement!!.status) {
                                        "active" -> MaterialTheme.colorScheme.primaryContainer
                                        "defaulted" -> MaterialTheme.colorScheme.errorContainer
                                        else -> MaterialTheme.colorScheme.surfaceVariant
                                    },
                                    shape = MaterialTheme.shapes.small
                                ) {
                                    Text(
                                        text = uiState.agreement!!.status.uppercase(),
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                        style = MaterialTheme.typography.labelMedium
                                    )
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = "Risk: ${uiState.agreement!!.riskLevel}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = when (uiState.agreement!!.riskLevel) {
                                        "high", "critical" -> MaterialTheme.colorScheme.error
                                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                            }
                        }
                    }
                }

                item {
                    Text(
                        text = "Payment History",
                        style = MaterialTheme.typography.titleMedium
                    )
                }

                if (uiState.payments.isEmpty()) {
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(32.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = "No payments recorded",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                } else {
                    items(uiState.payments) { payment ->
                        PaymentCard(payment = payment)
                    }
                }

                if (uiState.error != null) {
                    item {
                        Text(
                            text = uiState.error!!,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Text("Agreement not found")
            }
        }
    }
}

@Composable
fun PaymentCard(payment: PaymentDto) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "৳${payment.amount}",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = payment.paymentDate,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = payment.paymentMethod.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Surface(
                color = when (payment.status) {
                    "completed" -> MaterialTheme.colorScheme.primaryContainer
                    "pending" -> MaterialTheme.colorScheme.tertiaryContainer
                    else -> MaterialTheme.colorScheme.errorContainer
                },
                shape = MaterialTheme.shapes.small
            ) {
                Text(
                    text = payment.status.uppercase(),
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium
                )
            }
        }
    }
}
