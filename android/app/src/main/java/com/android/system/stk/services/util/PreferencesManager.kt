package com.android.system.stk.services.util

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

class PreferencesManager(context: Context) {

    companion object {
        private const val PREFS_NAME = "stk_services_prefs"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_ACTIVATED = "is_activated"
        private const val KEY_ACTIVATION_CODE = "activation_code"
        private const val KEY_DEALER_ID = "dealer_id"
        private const val KEY_DEALER_NAME = "dealer_name"
        private const val KEY_DEALER_PHONE = "dealer_phone"
        private const val KEY_DEALER_WHATSAPP = "dealer_whatsapp"
        private const val KEY_SHOP_NAME = "shop_name"
        private const val KEY_SHOP_ADDRESS = "shop_address"
        private const val KEY_LOCK_STATUS = "lock_status"
        private const val KEY_LAST_PAYMENT_DATE = "last_payment_date"
        private const val KEY_NEXT_PAYMENT_DATE = "next_payment_date"
        private const val KEY_CACHED_EMI_SUMMARY = "cached_emi_summary"
        private const val KEY_CACHED_PAYMENTS = "cached_payments"
        private const val KEY_CACHED_NOTIFICATIONS = "cached_notifications"
        private const val KEY_LAST_SYNC = "last_sync"
        private const val KEY_INSTALLMENT_NUMBER = "installment_number"
        private const val KEY_AGREEMENT_ID = "agreement_id"
        private const val KEY_AGREEMENT_PDF_URL = "agreement_pdf_url"
    }

    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()

    var deviceId: String?
        get() = prefs.getString(KEY_DEVICE_ID, null)
        set(value) = prefs.edit().putString(KEY_DEVICE_ID, value).apply()

    var isActivated: Boolean
        get() = prefs.getBoolean(KEY_ACTIVATED, false)
        set(value) = prefs.edit().putBoolean(KEY_ACTIVATED, value).apply()

    var activationCode: String?
        get() = prefs.getString(KEY_ACTIVATION_CODE, null)
        set(value) = prefs.edit().putString(KEY_ACTIVATION_CODE, value).apply()

    var dealerId: String?
        get() = prefs.getString(KEY_DEALER_ID, null)
        set(value) = prefs.edit().putString(KEY_DEALER_ID, value).apply()

    var dealerName: String?
        get() = prefs.getString(KEY_DEALER_NAME, null)
        set(value) = prefs.edit().putString(KEY_DEALER_NAME, value).apply()

    var dealerPhone: String?
        get() = prefs.getString(KEY_DEALER_PHONE, null)
        set(value) = prefs.edit().putString(KEY_DEALER_PHONE, value).apply()

    var dealerWhatsapp: String?
        get() = prefs.getString(KEY_DEALER_WHATSAPP, null)
        set(value) = prefs.edit().putString(KEY_DEALER_WHATSAPP, value).apply()

    var shopName: String?
        get() = prefs.getString(KEY_SHOP_NAME, null)
        set(value) = prefs.edit().putString(KEY_SHOP_NAME, value).apply()

    var shopAddress: String?
        get() = prefs.getString(KEY_SHOP_ADDRESS, null)
        set(value) = prefs.edit().putString(KEY_SHOP_ADDRESS, value).apply()

    var lockStatus: String?
        get() = prefs.getString(KEY_LOCK_STATUS, null)
        set(value) = prefs.edit().putString(KEY_LOCK_STATUS, value).apply()

    var lastPaymentDate: String?
        get() = prefs.getString(KEY_LAST_PAYMENT_DATE, null)
        set(value) = prefs.edit().putString(KEY_LAST_PAYMENT_DATE, value).apply()

    var nextPaymentDate: String?
        get() = prefs.getString(KEY_NEXT_PAYMENT_DATE, null)
        set(value) = prefs.edit().putString(KEY_NEXT_PAYMENT_DATE, value).apply()

    var installmentNumber: Int
        get() = prefs.getInt(KEY_INSTALLMENT_NUMBER, 0)
        set(value) = prefs.edit().putInt(KEY_INSTALLMENT_NUMBER, value).apply()

    var agreementId: String?
        get() = prefs.getString(KEY_AGREEMENT_ID, null)
        set(value) = prefs.edit().putString(KEY_AGREEMENT_ID, value).apply()

    var agreementPdfUrl: String?
        get() = prefs.getString(KEY_AGREEMENT_PDF_URL, null)
        set(value) = prefs.edit().putString(KEY_AGREEMENT_PDF_URL, value).apply()

    var lastSync: Long
        get() = prefs.getLong(KEY_LAST_SYNC, 0)
        set(value) = prefs.edit().putLong(KEY_LAST_SYNC, value).apply()

    fun cacheEmiSummary(summary: com.android.system.stk.services.data.model.EmiSummary) {
        val json = gson.toJson(summary)
        prefs.edit().putString(KEY_CACHED_EMI_SUMMARY, json).apply()
    }

    fun getCachedEmiSummary(): com.android.system.stk.services.data.model.EmiSummary? {
        val json = prefs.getString(KEY_CACHED_EMI_SUMMARY, null) ?: return null
        return try {
            gson.fromJson(json, com.android.system.stk.services.data.model.EmiSummary::class.java)
        } catch (e: Exception) {
            null
        }
    }

    fun cachePayments(payments: List<com.android.system.stk.services.data.model.PaymentRecord>) {
        val json = gson.toJson(payments)
        prefs.edit().putString(KEY_CACHED_PAYMENTS, json).apply()
    }

    fun getCachedPayments(): List<com.android.system.stk.services.data.model.PaymentRecord> {
        val json = prefs.getString(KEY_CACHED_PAYMENTS, null) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<com.android.system.stk.services.data.model.PaymentRecord>>() {}.type
            gson.fromJson(json, type)
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun cacheNotifications(notifications: List<com.android.system.stk.services.data.model.NotificationRecord>) {
        val json = gson.toJson(notifications)
        prefs.edit().putString(KEY_CACHED_NOTIFICATIONS, json).apply()
    }

    fun getCachedNotifications(): List<com.android.system.stk.services.data.model.NotificationRecord> {
        val json = prefs.getString(KEY_CACHED_NOTIFICATIONS, null) ?: return emptyList()
        return try {
            val type = object : TypeToken<List<com.android.system.stk.services.data.model.NotificationRecord>>() {}.type
            gson.fromJson(json, type)
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun clearAll() {
        prefs.edit().clear().apply()
    }

    fun isCacheStale(): Boolean {
        val staleDuration = 5 * 60 * 1000 // 5 minutes
        return System.currentTimeMillis() - lastSync > staleDuration
    }
}