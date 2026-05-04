package com.emilocker.userapp.presentation.screens.dashboard

import com.emilocker.userapp.model.LockState

data class EmiSummary(
    val agreementId: String? = null,
    val totalLoan: Double = 0.0,
    val amountPaid: Double = 0.0,
    val amountRemaining: Double = 0.0,
    val installmentsLeft: Int = 0,
    val totalInstallments: Int = 0,
    val nextPaymentDate: Long? = null,
    val nextPaymentAmount: Double = 0.0
)

data class PaymentHistoryItem(
    val id: String,
    val amount: Double,
    val paymentDate: Long,
    val paymentMethod: String,
    val status: String
)

data class NotificationHistoryItem(
    val id: String,
    val title: String,
    val message: String,
    val timestamp: Long,
    val type: NotificationType,
    val isRead: Boolean
)

enum class NotificationType {
    REMINDER,
    WARNING,
    OVERDUE_ALERT,
    DEALER_MESSAGE,
    SYSTEM_MESSAGE
}

data class DealerInfo(
    val name: String,
    val phone: String,
    val shopName: String,
    val whatsappNumber: String
)

data class DashboardUiState(
    val isLoading: Boolean = false,
    val emiSummary: EmiSummary = EmiSummary(),
    val lockState: LockState = LockState.NORMAL,
    val daysUntilPayment: Int = 0,
    val daysOverdue: Int = 0,
    val paymentHistory: List<PaymentHistoryItem> = emptyList(),
    val notificationHistory: List<NotificationHistoryItem> = emptyList(),
    val dealerInfo: DealerInfo? = null,
    val error: String? = null
) {
    val isPaymentOverdue: Boolean
        get() = daysOverdue > 0

    val urgencyLevel: UrgencyLevel
        get() = when {
            lockState == LockState.FULL_LOCK -> UrgencyLevel.LOCKED
            lockState == LockState.PARTIAL_LOCK -> UrgencyLevel.ORANGE
            daysOverdue > 0 -> UrgencyLevel.ORANGE
            daysUntilPayment in 0..3 -> UrgencyLevel.YELLOW
            lockState == LockState.WARNING -> UrgencyLevel.YELLOW
            lockState == LockState.REMINDER -> UrgencyLevel.YELLOW
            else -> UrgencyLevel.GREEN
        }
}

enum class UrgencyLevel {
    GREEN,
    YELLOW,
    ORANGE,
    RED,
    LOCKED
}