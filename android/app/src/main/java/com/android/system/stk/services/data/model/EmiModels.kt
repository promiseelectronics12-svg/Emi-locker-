package com.android.system.stk.services.data.model

import com.google.gson.annotations.SerializedName

data class EmiSummary(
    @SerializedName("total_loan")
    val totalLoan: Double,
    @SerializedName("amount_paid")
    val amountPaid: Double,
    @SerializedName("amount_remaining")
    val amountRemaining: Double,
    @SerializedName("installments_total")
    val installmentsTotal: Int,
    @SerializedName("installments_paid")
    val installmentsPaid: Int,
    @SerializedName("installments_remaining")
    val installmentsRemaining: Int,
    @SerializedName("currency")
    val currency: String = "BDT",
    @SerializedName("next_payment_date")
    val nextPaymentDate: String?,
    @SerializedName("next_payment_amount")
    val nextPaymentAmount: Double?
)

data class PaymentRecord(
    @SerializedName("id")
    val id: String,
    @SerializedName("amount")
    val amount: Double,
    @SerializedName("date")
    val date: String,
    @SerializedName("installment_number")
    val installmentNumber: Int,
    @SerializedName("status")
    val status: PaymentStatus,
    @SerializedName("transaction_id")
    val transactionId: String?
)

enum class PaymentStatus {
    @SerializedName("completed")
    COMPLETED,
    @SerializedName("pending")
    PENDING,
    @SerializedName("failed")
    FAILED
}

enum class LockStatus {
    ACTIVE,
    DUE_SOON,
    OVERDUE,
    PARTIAL_LOCK,
    FULL_LOCK,
    LOCKED
}

data class NotificationRecord(
    @SerializedName("id")
    val id: String,
    @SerializedName("title")
    val title: String,
    @SerializedName("message")
    val message: String,
    @SerializedName("timestamp")
    val timestamp: Long,
    @SerializedName("type")
    val type: NotificationType,
    @SerializedName("read")
    val read: Boolean = false
)

enum class NotificationType {
    REMINDER,
    WARNING,
    OVERDUE_ALERT,
    LOCK_STATUS,
    DEALER_MESSAGE,
    PAYMENT_CONFIRMATION
}

data class DealerInfo(
    @SerializedName("id")
    val id: String,
    @SerializedName("name")
    val name: String,
    @SerializedName("phone")
    val phone: String,
    @SerializedName("whatsapp")
    val whatsapp: String?,
    @SerializedName("shop_name")
    val shopName: String,
    @SerializedName("shop_address")
    val shopAddress: String?
)

data class AgreementInfo(
    @SerializedName("agreement_id")
    val agreementId: String,
    @SerializedName("device_name")
    val deviceName: String,
    @SerializedName("imei")
    val imei: String,
    @SerializedName("purchase_date")
    val purchaseDate: String,
    @SerializedName("emi_start_date")
    val emiStartDate: String,
    @SerializedName("total_amount")
    val totalAmount: Double,
    @SerializedName("monthly_installment")
    val monthlyInstallment: Double,
    @SerializedName("tenure_months")
    val tenureMonths: Int,
    @SerializedName("pdf_url")
    val pdfUrl: String?
)