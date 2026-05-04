package com.android.system.stk.services.util

import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.*

object FormatUtils {

    private val currencyFormat = NumberFormat.getCurrencyInstance(Locale("en", "BD"))
    private val dateFormat = SimpleDateFormat("dd MMM yyyy", Locale.getDefault())
    private val dateTimeFormat = SimpleDateFormat("dd MMM yyyy, hh:mm a", Locale.getDefault())
    private val apiDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())

    fun formatCurrency(amount: Double, currency: String = "BDT"): String {
        return try {
            val format = NumberFormat.getCurrencyInstance(Locale("en", "BD"))
            format.maximumFractionDigits = 2
            format.minimumFractionDigits = 2
            format.format(amount)
        } catch (e: Exception) {
            "$currency ${String.format("%.2f", amount)}"
        }
    }

    fun formatDate(timestamp: Long): String {
        return try {
            val date = Date(timestamp)
            dateFormat.format(date)
        } catch (e: Exception) {
            ""
        }
    }

    fun formatDateTime(timestamp: Long): String {
        return try {
            val date = Date(timestamp)
            dateTimeFormat.format(date)
        } catch (e: Exception) {
            ""
        }
    }

    fun parseApiDate(dateString: String?): Date? {
        if (dateString.isNullOrEmpty()) return null
        return try {
            apiDateFormat.parse(dateString)
        } catch (e: Exception) {
            null
        }
    }

    fun formatDateFromString(dateString: String?): String {
        val date = parseApiDate(dateString) ?: return "N/A"
        return dateFormat.format(date)
    }

    fun maskPhoneNumber(phone: String): String {
        return if (phone.length > 4) {
            val visibleDigits = phone.takeLast(4)
            val maskedPart = "*".repeat(phone.length - 4)
            "$maskedPart$visibleDigits"
        } else {
            phone
        }
    }

    fun formatInstallmentProgress(paid: Int, total: Int): String {
        return "$paid / $total"
    }
}