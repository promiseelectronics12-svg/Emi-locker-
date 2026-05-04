package com.android.system.stk.services.util

import android.content.Context
import com.android.system.stk.services.BuildConfig

object ApiConfig {
    private const val DEFAULT_API_BASE_URL = "http://localhost:3000"

    fun getApiBaseUrl(context: Context): String {
        return try {
            val metadata = context.packageManager
                .getApplicationInfo(context.packageName, android.content.pm.PackageManager.GET_META_DATA)
                .metaData
            metadata.getString("API_BASE_URL", DEFAULT_API_BASE_URL) ?: DEFAULT_API_BASE_URL
        } catch (e: Exception) {
            BuildConfig.API_BASE_URL.ifEmpty { DEFAULT_API_BASE_URL }
        }
    }

    fun isDevMode(context: Context): Boolean {
        val baseUrl = getApiBaseUrl(context)
        return baseUrl.contains("localhost") || baseUrl.contains("10.0.2.2")
    }

    fun getDashboardUrl(context: Context): String {
        return "${getApiBaseUrl(context)}/api/v1/dashboard"
    }

    fun getPaymentsUrl(context: Context): String {
        return "${getApiBaseUrl(context)}/api/v1/payments"
    }

    fun getNotificationsUrl(context: Context): String {
        return "${getApiBaseUrl(context)}/api/v1/notifications"
    }

    fun getDealerUrl(context: Context): String {
        return "${getApiBaseUrl(context)}/api/v1/dealer"
    }

    fun getAgreementUrl(context: Context): String {
        return "${getApiBaseUrl(context)}/api/v1/agreement"
    }

    fun getDeviceStatusUrl(context: Context): String {
        return "${getApiBaseUrl(context)}/api/v1/device/status"
    }
}