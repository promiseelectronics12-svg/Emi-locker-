package com.android.system.stk.services.data.repository

import android.content.Context
import android.os.Build
import android.telephony.TelephonyManager
import android.util.Base64
import com.android.system.stk.services.data.model.*
import com.android.system.stk.services.util.ApiConfig
import com.android.system.stk.services.util.NetworkClient
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.concurrent.ConcurrentHashMap

class EmiRepository {

    private val gson = Gson()
    private var cachedClient: OkHttpClient? = null
    private var cachedBaseUrl: String? = null
    private val secureRandom = SecureRandom()
    private val usedNonces = ConcurrentHashMap<String, Long>()
    private val MAX_VALIDITY_WINDOW_MS = 24 * 60 * 60 * 1000L

    private fun getClient(context: android.content.Context): OkHttpClient {
        val baseUrl = ApiConfig.getApiBaseUrl(context)
        if (cachedClient == null || cachedBaseUrl != baseUrl) {
            cachedClient = NetworkClient.createOkHttpClient(context)
            cachedBaseUrl = baseUrl
        }
        return cachedClient!!
    }

    private fun getDeviceImei(context: Context): String {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                tm.imei ?: getDeviceSerial()
            } else {
                @Suppress("DEPRECATION")
                tm.deviceId ?: getDeviceSerial()
            }
        } catch (e: SecurityException) {
            getDeviceSerial()
        }
    }

    private fun getDeviceSerial(): String {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Build.getSerial()
            } else {
                @Suppress("DEPRECATION")
                Build.SERIAL
            }
        } catch (e: SecurityException) {
            "UNKNOWN_SERIAL"
        }
    }

    private fun generateNonce(): String {
        val nonceBytes = ByteArray(32)
        secureRandom.nextBytes(nonceBytes)
        return Base64.encodeToString(nonceBytes, Base64.NO_WRAP)
    }

    private fun generateHmacSignature(
        deviceId: String,
        imei: String,
        serial: String,
        nonce: String,
        timestamp: Long,
        actionType: String
    ): String {
        val hardwareBinding = "$deviceId|$imei|$serial"
        val payload = "$hardwareBinding|$timestamp|$nonce|$actionType"

        val mac = Mac.getInstance("HmacSHA256")
        val keySpec = SecretKeySpec(deviceId.toByteArray(StandardCharsets.UTF_8), "HmacSHA256")
        mac.init(keySpec)
        val signatureBytes = mac.doFinal(payload.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(signatureBytes, Base64.NO_WRAP)
    }

    private fun isValidNonce(nonce: String): Boolean {
        if (usedNonces.containsKey(nonce)) {
            return false
        }
        usedNonces[nonce] = System.currentTimeMillis()
        cleanupExpiredNonces()
        return true
    }

    private fun cleanupExpiredNonces() {
        val cutoff = System.currentTimeMillis() - MAX_VALIDITY_WINDOW_MS
        usedNonces.entries.removeIf { it.value < cutoff }
    }

    private fun createSignedRequest(
        context: Context,
        deviceId: String,
        url: String,
        actionType: String,
        isPost: Boolean = false,
        body: okhttp3.RequestBody? = null
    ): Request.Builder {
        val imei = getDeviceImei(context)
        val serial = getDeviceSerial()
        val nonce = generateNonce()
        val timestamp = System.currentTimeMillis()

        val signature = generateHmacSignature(deviceId, imei, serial, nonce, timestamp, actionType)

        val builder = if (isPost) {
            Request.Builder()
                .url(url)
                .post(body!!)
        } else {
            Request.Builder()
                .url(url)
                .get()
        }

        return builder
            .header("X-Command-Signature", signature)
            .header("X-Command-Nonce", nonce)
            .header("X-Timestamp", timestamp.toString())
            .header("X-Device-Imei", imei)
            .header("X-Device-Serial", serial)
    }

    suspend fun getEmiSummary(context: android.content.Context, deviceId: String): Result<EmiSummary> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val url = "${ApiConfig.getDashboardUrl(context)}?device_id=$deviceId"
            val requestBuilder = createSignedRequest(context, deviceId, url, "GET_EMI_SUMMARY")
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string()
                val summary = gson.fromJson(body, EmiSummary::class.java)
                Result.success(summary)
            } else {
                Result.failure(Exception("Failed to fetch EMI summary: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getPaymentHistory(context: android.content.Context, deviceId: String): Result<List<PaymentRecord>> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val url = "${ApiConfig.getPaymentsUrl(context)}?device_id=$deviceId"
            val requestBuilder = createSignedRequest(context, deviceId, url, "GET_PAYMENT_HISTORY")
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string()
                val payments = gson.fromJson(body, Array<PaymentRecord>::class.java).toList()
                Result.success(payments)
            } else {
                Result.failure(Exception("Failed to fetch payment history: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getNotifications(context: android.content.Context, deviceId: String): Result<List<NotificationRecord>> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val url = "${ApiConfig.getNotificationsUrl(context)}?device_id=$deviceId"
            val requestBuilder = createSignedRequest(context, deviceId, url, "GET_NOTIFICATIONS")
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string()
                val notifications = gson.fromJson(body, Array<NotificationRecord>::class.java).toList()
                Result.success(notifications)
            } else {
                Result.failure(Exception("Failed to fetch notifications: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getDealerInfo(context: android.content.Context, deviceId: String): Result<DealerInfo> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val url = "${ApiConfig.getDealerUrl(context)}?device_id=$deviceId"
            val requestBuilder = createSignedRequest(context, deviceId, url, "GET_DEALER_INFO")
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string()
                val dealer = gson.fromJson(body, DealerInfo::class.java)
                Result.success(dealer)
            } else {
                Result.failure(Exception("Failed to fetch dealer info: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getAgreement(context: android.content.Context, deviceId: String): Result<AgreementInfo> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val url = "${ApiConfig.getAgreementUrl(context)}?device_id=$deviceId"
            val requestBuilder = createSignedRequest(context, deviceId, url, "GET_AGREEMENT")
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string()
                val agreement = gson.fromJson(body, AgreementInfo::class.java)
                Result.success(agreement)
            } else {
                Result.failure(Exception("Failed to fetch agreement: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getDeviceStatus(context: android.content.Context, deviceId: String): Result<LockStatus> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val url = "${ApiConfig.getDeviceStatusUrl(context)}?device_id=$deviceId"
            val requestBuilder = createSignedRequest(context, deviceId, url, "GET_DEVICE_STATUS")
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            if (response.isSuccessful) {
                val body = response.body?.string()
                val status = gson.fromJson(body, LockStatus::class.java)
                Result.success(status)
            } else {
                Result.failure(Exception("Failed to fetch device status: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun markNotificationRead(context: android.content.Context, notificationId: String): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val client = getClient(context)
            val deviceId = getDeviceIdFromPreferences(context)
            val json = """{"notification_id": "$notificationId"}"""
            val body = json.toRequestBody("application/json".toMediaType())

            val url = "${ApiConfig.getNotificationsUrl(context)}/read"
            val requestBuilder = createSignedRequest(
                context,
                deviceId,
                url,
                "MARK_NOTIFICATION_READ",
                isPost = true,
                body = body
            )
            val request = requestBuilder.build()

            val response = client.newCall(request).execute()
            Result.success(response.isSuccessful)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun getDeviceIdFromPreferences(context: Context): String {
        return try {
            val prefs = context.getSharedPreferences("emi_prefs", Context.MODE_PRIVATE)
            prefs.getString("device_id", "") ?: ""
        } catch (e: Exception) {
            ""
        }
    }
}