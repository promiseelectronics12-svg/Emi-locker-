package com.emilocker.userapp.security

import android.util.Log
import com.emilocker.userapp.BuildConfig
import okhttp3.CertificatePinner
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CertificatePinnerConfig @Inject constructor() {
    private val TAG = "CertificatePinner"

    fun buildCertificatePinner(): CertificatePinner? {
        val baseUrl = BuildConfig.API_BASE_URL

        if (isDevEnvironment(baseUrl)) {
            Log.d(TAG, "Development environment detected ($baseUrl), skipping certificate pinning")
            return null
        }

        val host = extractHost(baseUrl)
        if (host.isEmpty()) {
            Log.w(TAG, "Could not extract host from $baseUrl, skipping certificate pinning")
            return null
        }

        val sslPin = BuildConfig.SSL_PIN
        if (sslPin.isEmpty() || sslPin.contains("REPLACE_BEFORE_PRODUCTION")) {
            Log.w(TAG, "SSL_PIN not properly configured, skipping certificate pinning")
            return null
        }

        return try {
            CertificatePinner.Builder()
                .add(host, sslPin)
                .build()
                .also {
                    Log.d(TAG, "Certificate pinning configured for host: $host with pin: $sslPin")
                }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build certificate pinner", e)
            null
        }
    }

    fun validateCertificatePinning(host: String, validatedCerts: List<String>): Boolean {
        val baseUrl = BuildConfig.API_BASE_URL

        if (isDevEnvironment(baseUrl)) {
            return true
        }

        val configuredPin = BuildConfig.SSL_PIN
        if (configuredPin.isEmpty() || configuredPin.contains("REPLACE_BEFORE_PRODUCTION")) {
            Log.w(TAG, "SSL_PIN not configured, skipping validation")
            return true
        }

        val normalizedHost = extractHost(baseUrl)
        if (normalizedHost != host) {
            Log.w(TAG, "Host mismatch: expected $normalizedHost, got $host")
            return false
        }

        val formattedPin = "sha256/${validatedCerts.firstOrNull()?.replace(":", "")}"
        val isValid = formattedPin == configuredPin || validatedCerts.any { cert ->
            "sha256/${cert.replace(":", "")}" == configuredPin
        }

        if (!isValid) {
            Log.e(TAG, "Certificate pinning validation FAILED for $host")
            logSecurityEvent("PIN_VALIDATION_FAILED", host)
        }

        return isValid
    }

    private fun isDevEnvironment(baseUrl: String): Boolean {
        return baseUrl.contains("localhost") ||
                baseUrl.contains("10.0.2.2") ||
                baseUrl.contains("127.0.0.1") ||
                baseUrl.contains("0.0.0.0") ||
                baseUrl.contains("staging") ||
                baseUrl.contains("dev")
    }

    private fun extractHost(urlString: String): String {
        return try {
            val url = URL(urlString)
            url.host
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse URL: $urlString", e)
            ""
        }
    }

    private fun logSecurityEvent(eventType: String, details: String) {
        Log.w(TAG, "SECURITY_EVENT: $eventType - $details")
    }
}