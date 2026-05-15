package com.android.simtoolkit.presentation.screens.dashboard

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.data.remote.api.PaymentDto
import com.android.simtoolkit.model.LockState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val apiService: ApiService,
    private val preferencesManager: PreferencesManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()

    companion object {
        private const val TAG = "DashboardViewModel"
    }

    init {
        loadDashboardData()
    }

    fun loadDashboardData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            if (preferencesManager.accessToken.first().isNullOrEmpty()) {
                _uiState.update { it.copy(isLoading = false, error = "Authentication required") }
                return@launch
            }

            try {
                val lockState = preferencesManager.getCurrentLockState()
                val dealerName = preferencesManager.dealerName.first()
                val dealerPhone = preferencesManager.dealerPhone.first()
                val amountDueStr = preferencesManager.amountDue.first()
                val daysOverdue = preferencesManager.daysOverdue.first() ?: 0

                val dealerInfo = if (dealerName != null && dealerPhone != null) {
                    DealerInfo(
                        name = dealerName,
                        phone = dealerPhone,
                        shopName = dealerName,
                        whatsappNumber = dealerPhone.replace("[^0-9+]".toRegex(), "")
                    )
                } else {
                    null
                }

                val amountDue = amountDueStr?.toDoubleOrNull() ?: 0.0

                val agreementsResult = try {
                    apiService.getAgreements()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to fetch agreements", e)
                    _uiState.update { it.copy(isLoading = false, error = "Network error: Unable to load agreements. Please check your connection.") }
                    return@launch
                }

                val paymentsResult = try {
                    apiService.getPaymentHistory()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to fetch payments", e)
                    _uiState.update { it.copy(isLoading = false, error = "Network error: Unable to load payment history. Please check your connection.") }
                    return@launch
                }

                val emiSummary = calculateEmiSummary(
                    agreementsResult?.body(),
                    paymentsResult?.body(),
                    amountDue,
                    lockState
                )

                val paymentHistory = paymentsResult?.body()?.payments?.map { it.toPaymentHistoryItem() } ?: emptyList()

                val notificationHistory = loadNotificationHistory()

                _uiState.update { state ->
                    state.copy(
                        isLoading = false,
                        emiSummary = emiSummary,
                        lockState = lockState,
                        dealerInfo = dealerInfo,
                        paymentHistory = paymentHistory,
                        notificationHistory = notificationHistory,
                        daysUntilPayment = calculateDaysUntilPayment(emiSummary.nextPaymentDate),
                        daysOverdue = daysOverdue
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load dashboard data"
                    )
                }
            }
        }
    }

    private fun calculateEmiSummary(
        agreementsResponse: com.android.simtoolkit.data.remote.api.AgreementListResponse?,
        paymentsResponse: com.android.simtoolkit.data.remote.api.PaymentListResponse?,
        currentAmountDue: Double,
        lockState: LockState
    ): EmiSummary {
        val agreements = agreementsResponse?.agreements ?: emptyList()
        val payments = paymentsResponse?.payments ?: emptyList()

        if (agreements.isEmpty()) {
            return EmiSummary()
        }

        val primaryAgreement = agreements.first()
        val totalPaid = payments.sumOf { it.amount }

        val nextPaymentDate = calculateNextPaymentDate(primaryAgreement.startDate, primaryAgreement.tenureMonths, payments.size)

        return EmiSummary(
            agreementId = primaryAgreement.id,
            totalLoan = primaryAgreement.totalAmount,
            amountPaid = totalPaid,
            amountRemaining = primaryAgreement.totalAmount - totalPaid,
            installmentsLeft = primaryAgreement.tenureMonths - payments.size,
            totalInstallments = primaryAgreement.tenureMonths,
            nextPaymentDate = nextPaymentDate,
            nextPaymentAmount = primaryAgreement.monthlyPayment
        )
    }

    private fun calculateNextPaymentDate(startDateStr: String, tenureMonths: Int, paymentsMade: Int): Long? {
        return try {
            val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val startDate = dateFormat.parse(startDateStr) ?: return null

            val calendar = Calendar.getInstance()
            calendar.time = startDate
            calendar.add(Calendar.MONTH, paymentsMade)

            if (paymentsMade >= tenureMonths) {
                null
            } else {
                calendar.timeInMillis
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun calculateDaysUntilPayment(nextPaymentDate: Long?): Int {
        if (nextPaymentDate == null) return 0

        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val paymentDay = Calendar.getInstance().apply {
            timeInMillis = nextPaymentDate
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val diffMillis = paymentDay - today
        return (diffMillis / (1000 * 60 * 60 * 24)).toInt()
    }

    private fun loadNotificationHistory(): List<NotificationHistoryItem> {
        val notifications = mutableListOf<NotificationHistoryItem>()
        val now = System.currentTimeMillis()

        when (_uiState.value.lockState) {
            LockState.REMINDER -> {
                notifications.add(
                    NotificationHistoryItem(
                        id = "reminder_${now}",
                        title = "Payment Reminder",
                        message = "Your EMI payment is due in ${_uiState.value.daysUntilPayment} days",
                        timestamp = now - (24 * 60 * 60 * 1000),
                        type = NotificationType.REMINDER,
                        isRead = false
                    )
                )
            }
            LockState.WARNING -> {
                notifications.add(
                    NotificationHistoryItem(
                        id = "warning_${now}",
                        title = "Payment Warning",
                        message = "Your EMI payment is due in ${_uiState.value.daysUntilPayment} days. Please make payment immediately.",
                        timestamp = now - (12 * 60 * 60 * 1000),
                        type = NotificationType.WARNING,
                        isRead = false
                    )
                )
            }
            LockState.OVERDUE_ALERT -> {
                notifications.add(
                    NotificationHistoryItem(
                        id = "overdue_${now}",
                        title = "Payment Overdue",
                        message = "Your EMI payment is overdue by ${_uiState.value.daysOverdue} days.",
                        timestamp = now - (6 * 60 * 60 * 1000),
                        type = NotificationType.OVERDUE_ALERT,
                        isRead = false
                    )
                )
            }
            LockState.FULL_LOCK -> {
                notifications.add(
                    NotificationHistoryItem(
                        id = "full_lock_${now}",
                        title = "Device Fully Locked",
                        message = "Your device is locked. Contact your dealer or emergency services.",
                        timestamp = now,
                        type = NotificationType.OVERDUE_ALERT,
                        isRead = false
                    )
                )
            }
            LockState.NORMAL -> {
                if (_uiState.value.daysUntilPayment in 1..7) {
                    notifications.add(
                        NotificationHistoryItem(
                            id = "reminder_${now}",
                            title = "Upcoming Payment",
                            message = "Your next EMI payment is due in ${_uiState.value.daysUntilPayment} days",
                            timestamp = now - (24 * 60 * 60 * 1000),
                            type = NotificationType.REMINDER,
                            isRead = true
                        )
                    )
                }
            }
        }

        return notifications.sortedByDescending { it.timestamp }
    }

    fun markNotificationAsRead(notificationId: String) {
        _uiState.update { state ->
            state.copy(
                notificationHistory = state.notificationHistory.map { notification ->
                    if (notification.id == notificationId) {
                        notification.copy(isRead = true)
                    } else {
                        notification
                    }
                }
            )
        }
    }

    fun refresh() {
        loadDashboardData()
    }

    fun getAgreementId(): String {
        return uiState.value.emiSummary.agreementId ?: ""
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    private fun PaymentDto.toPaymentHistoryItem(): PaymentHistoryItem {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val date = try {
            dateFormat.parse(this.paymentDate)?.time ?: System.currentTimeMillis()
        } catch (e: Exception) {
            System.currentTimeMillis()
        }

        return PaymentHistoryItem(
            id = this.id,
            amount = this.amount,
            paymentDate = date,
            paymentMethod = this.paymentMethod,
            status = this.status
        )
    }
}
