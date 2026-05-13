package com.android.simtoolkit.security.paut

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.telephony.TelephonyManager
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.android.simtoolkit.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PautManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val TAG = "PautManager"
    private val DATASTORE_NAME = "paut_secure_datastore"
    private val PAUT_KEY = "paut_token_encrypted"
    private val SERVER_PUBLIC_KEY_KEY = "server_public_key"
    private val PAUT_USED_KEY = "paut_used_"
    private val PAUT_USED_VERSION_KEY = "paut_used_version"
    private val PAUT_USED_TIMESTAMP_KEY = "paut_used_timestamp_"
    private val CLOCK_SKEW_TOLERANCE_MS = 45_000L
    private val MAX_VALIDITY_WINDOW_MS = 2 * 60 * 60 * 1000L
    private val IV_SIZE_BYTES = 12

    private val usedNonces = ConcurrentHashMap<String, Long>()
    private val secureRandom = SecureRandom()

    private val encryptedPrefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            DATASTORE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    suspend fun storePaut(jwtToken: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val encrypted = encryptToken(jwtToken)
            encryptedPrefs.edit().putString(PAUT_KEY, encrypted).apply()
            Log.d(TAG, "PAUT stored successfully")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to store PAUT", e)
            Result.failure(e)
        }
    }

    suspend fun getStoredPaut(): String? = withContext(Dispatchers.IO) {
        try {
            val encrypted = encryptedPrefs.getString(PAUT_KEY, null) ?: return@withContext null
            decryptToken(encrypted)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to retrieve PAUT", e)
            null
        }
    }

    suspend fun clearPaut() = withContext(Dispatchers.IO) {
        try {
            encryptedPrefs.edit().remove(PAUT_KEY).apply()
            Log.d(TAG, "PAUT cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear PAUT", e)
        }
    }

    suspend fun generateNonce(): String {
        val nonceBytes = ByteArray(32)
        secureRandom.nextBytes(nonceBytes)
        return Base64.encodeToString(nonceBytes, Base64.NO_WRAP)
    }

    private fun isNonceValid(nonce: String, expiresAt: Long): Boolean {
        val now = System.currentTimeMillis()
        if (now > expiresAt + MAX_VALIDITY_WINDOW_MS) {
            return false
        }
        val timestamp = usedNonces.putIfAbsent(nonce, now)
        if (timestamp != null) {
            Log.w(TAG, "Duplicate nonce detected: $nonce")
            return false
        }
        cleanupExpiredNonces(expiresAt)
        return true
    }

    private fun cleanupExpiredNonces(tokenExpiresAt: Long) {
        val cutoff = minOf(tokenExpiresAt, System.currentTimeMillis() - MAX_VALIDITY_WINDOW_MS)
        usedNonces.entries.removeIf { it.value < cutoff }
    }

    private fun parseJwtPayload(token: String): Map<String, Any>? {
        val parts = token.split(".")
        if (parts.size != 3) return null

        return try {
            val headerJson = String(Base64.decode(parts[0], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING))
            val headerMap = parseJsonToMap(headerJson)
            val algorithm = headerMap["alg"] as? String
            if (algorithm == null || algorithm != "HS256") {
                Log.w(TAG, "Invalid or missing algorithm in JWT header: $algorithm")
                return null
            }

            val payloadJson = String(Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING))
            val map = parseJsonToMap(payloadJson)

            val issuer = map["iss"] as? String
            val audience = map["aud"] as? String
            if (issuer == null) {
                Log.w(TAG, "Missing issuer (iss) claim in JWT")
                return null
            }

            map["_parsed"] = true
            map
        } catch (e: Exception) {
            Log.e(TAG, "JWT payload parse error", e)
            null
        }
    }

    private fun parseJsonToMap(json: String): MutableMap<String, Any> {
        val result = mutableMapOf<String, Any>()
        val cleanJson = json.trim().removePrefix("{").removeSuffix("}")
        cleanJson.split(",").forEach { entry ->
            val kv = entry.trim().split(":", limit = 2)
            if (kv.size == 2) {
                val k = kv[0].trim().trim('"')
                val v = kv[1].trim()
                when {
                    v.startsWith("\"") && v.endsWith("\"") -> result[k] = v.removeSurrounding("\"")
                    v == "true" -> result[k] = true
                    v == "false" -> result[k] = false
                    v.toLongOrNull() != null -> result[k] = v.toLong()
                    v.toDoubleOrNull() != null -> result[k] = v.toDouble()
                    else -> result[k] = v
                }
            }
        }
        return result
    }

    suspend fun verifyPaut(token: String, source: String = "UNKNOWN"): PautVerificationResult = withContext(Dispatchers.IO) {
        try {
            val parts = token.split(".")
            if (parts.size != 3) {
                logAuditFailure("INVALID_FORMAT", "Invalid JWT structure: expected 3 parts, got ${parts.size}", source, null)
                return@withContext PautVerificationResult.INVALID_FORMAT
            }

            val claims = parseJwtPayload(token)
            if (claims == null) {
                logAuditFailure("INVALID_FORMAT", "Failed to parse JWT payload", source, null)
                return@withContext PautVerificationResult.INVALID_FORMAT
            }

            val deviceImei = claims["deviceImei"]?.toString()
                ?: return@withContext PautVerificationResult.INVALID_FORMAT
            val expiresAtStr = claims["expiresAt"]?.toString()
                ?: return@withContext PautVerificationResult.INVALID_FORMAT
            val nonce = claims["nonce"]?.toString()
                ?: return@withContext PautVerificationResult.INVALID_FORMAT

            val currentDeviceFingerprint = getCompositeDeviceFingerprint()
            if (deviceImei != currentDeviceFingerprint) {
                logAuditFailure("IMEI_MISMATCH", "Device fingerprint mismatch", source, deviceImei)
                return@withContext PautVerificationResult.IMEI_MISMATCH
            }

            val expiresAt = expiresAtStr.toLongOrNull() ?: return@withContext PautVerificationResult.INVALID_FORMAT
            val currentTime = System.currentTimeMillis()
            if (currentTime > expiresAt + CLOCK_SKEW_TOLERANCE_MS) {
                logAuditFailure("EXPIRED", "Token expired at $expiresAt", source, deviceImei)
                return@withContext PautVerificationResult.EXPIRED
            }

            if (!isNonceValid(nonce, expiresAt)) {
                logAuditFailure("ALREADY_USED", "Nonce already used", source, deviceImei)
                return@withContext PautVerificationResult.ALREADY_USED
            }

            val hmacSecret = getServerPublicKey() ?: run {
                Log.e(TAG, "HMAC secret key not available")
                return@withContext PautVerificationResult.MISSING_PUBLIC_KEY
            }

            val signingInput = "${parts[0]}.${parts[1]}"
            val signatureBytes = Base64.decode(parts[2], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val isValidSignature = verifyHmacSignature(signingInput, Base64.encodeToString(signatureBytes, Base64.NO_WRAP), hmacSecret)

            if (!isValidSignature) {
                logAuditFailure("INVALID_SIGNATURE", "HMAC signature verification failed", source, deviceImei)
                return@withContext PautVerificationResult.INVALID_SIGNATURE
            }

            Log.d(TAG, "PAUT verified successfully")
            PautVerificationResult.VALID
        } catch (e: Exception) {
            Log.e(TAG, "PAUT verification error", e)
            PautVerificationResult.ERROR
        }
    }

    suspend fun checkAndExecutePaut(): PautExecutionResult = withContext(Dispatchers.IO) {
        val storedPaut = getStoredPaut() ?: return@withContext PautExecutionResult.NO_TOKEN

        val verificationResult = verifyPaut(storedPaut, source = "AUTO_CHECK")
        if (verificationResult != PautVerificationResult.VALID) {
            Log.w(TAG, "Stored PAUT not valid: $verificationResult")
            return@withContext PautExecutionResult.INVALID_TOKEN
        }

        try {
            val claims = parseJwtPayload(storedPaut) ?: return@withContext PautExecutionResult.INVALID_TOKEN
            val authorizedAt = claims["authorizedAt"]?.toString()?.toLongOrNull()
                ?: return@withContext PautExecutionResult.INVALID_TOKEN
            val nonce = claims["nonce"]?.toString() ?: return@withContext PautExecutionResult.INVALID_TOKEN

            val currentTime = System.currentTimeMillis()
            val twoHoursMs = 2 * 60 * 60 * 1000L
            if (currentTime < authorizedAt + twoHoursMs) {
                Log.d(TAG, "Too early to execute PAUT (authorizedAt=$authorizedAt, now=$currentTime)")
                return@withContext PautExecutionResult.TOO_EARLY
            }

            markPautAsUsedWithAtomicOperation(nonce, currentTime)
            queueServerReport(storedPaut, "PAUT_EXECUTED")

            Log.d(TAG, "PAUT executed and marked as used")
            PautExecutionResult.EXECUTED
        } catch (e: Exception) {
            Log.e(TAG, "PAUT execution error", e)
            PautExecutionResult.ERROR
        }
    }

    private fun markPautAsUsedWithAtomicOperation(nonce: String, timestamp: Long) {
        val currentVersion = encryptedPrefs.getInt(PAUT_USED_VERSION_KEY, 0)
        val newVersion = currentVersion + 1

        encryptedPrefs.edit()
            .putBoolean(PAUT_USED_KEY + nonce, true)
            .putLong(PAUT_USED_TIMESTAMP_KEY + nonce, timestamp)
            .putInt(PAUT_USED_VERSION_KEY, newVersion)
            .apply()

        Log.d(TAG, "PAUT marked as used atomically: nonce=$nonce, version=$newVersion, timestamp=$timestamp")
    }

    suspend fun markPautAsUsed(nonce: String) = withContext(Dispatchers.IO) {
        try {
            encryptedPrefs.edit()
                .putBoolean(PAUT_USED_KEY + nonce, true)
                .putLong(PAUT_USED_TIMESTAMP_KEY + nonce, System.currentTimeMillis())
                .apply()
            Log.d(TAG, "PAUT marked as used (nonce: $nonce)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mark PAUT as used", e)
        }
    }

    suspend fun isPautUsed(nonce: String): Boolean {
        return try {
            val used = encryptedPrefs.getBoolean(PAUT_USED_KEY + nonce, false)
            val timestamp = encryptedPrefs.getLong(PAUT_USED_TIMESTAMP_KEY + nonce, 0)

            if (used && timestamp > 0) {
                val version = encryptedPrefs.getInt(PAUT_USED_VERSION_KEY, 0)
                Log.d(TAG, "PAUT used status: nonce=$nonce, used=$used, timestamp=$timestamp, version=$version")
            }

            used
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check PAUT used status", e)
            false
        }
    }

    suspend fun queueServerReport(token: String, action: String) = withContext(Dispatchers.IO) {
        try {
            val timestamp = System.currentTimeMillis()
            val reportKey = "pending_report_${timestamp}"
            val reportValue = "$action|$timestamp|${token.take(20)}..."
            encryptedPrefs.edit().putString(reportKey, reportValue).apply()
            Log.d(TAG, "Server report queued: action=$action at $timestamp")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to queue server report", e)
        }
    }

    private fun logAuditFailure(reason: String, details: String, source: String, imei: String?) {
        val timestamp = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
            .format(java.util.Date())
        Log.w(TAG, "AUDIT_FAILURE|$timestamp|$reason|$details|source=$source|imei=${imei ?: "N/A"}")
    }

    private fun encryptToken(token: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val key = getOrCreateEncryptionKey()
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val iv = cipher.iv

        if (iv.size != IV_SIZE_BYTES) {
            throw SecurityException("IV must be exactly $IV_SIZE_BYTES bytes")
        }

        val encrypted = cipher.doFinal(token.toByteArray(StandardCharsets.UTF_8))
        val ivBase64 = Base64.encodeToString(iv, Base64.NO_WRAP)
        val encryptedBase64 = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        return "$ivBase64:$encryptedBase64"
    }

    private fun decryptToken(encryptedData: String): String {
        val parts = encryptedData.split(":")
        if (parts.size != 2) throw IllegalArgumentException("Invalid encrypted data format")

        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)

        if (iv.size != IV_SIZE_BYTES) {
            throw SecurityException("IV must be exactly $IV_SIZE_BYTES bytes")
        }

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val key = getOrCreateEncryptionKey()
        val spec = GCMParameterSpec(128, iv)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        val decrypted = cipher.doFinal(encrypted)
        return String(decrypted, StandardCharsets.UTF_8)
    }

    private fun getOrCreateEncryptionKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore")
        keyStore.load(null)

        val alias = "paut_encryption_key"
        if (keyStore.containsAlias(alias)) {
            val entry = keyStore.getEntry(alias, null) as KeyStore.SecretKeyEntry
            return entry.secretKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )

        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()

        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private fun getCompositeDeviceFingerprint(): String {
        val imei = getDeviceImei()
        val hardwareId = Build.HARDWARE
        val keystoreKey = getOrCreateKeystoreDeviceKey()
        val combined = "$imei|$hardwareId|$keystoreKey"
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(combined.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(hash, Base64.NO_WRAP)
    }

    private fun getOrCreateKeystoreDeviceKey(): String {
        val keyStore = KeyStore.getInstance("AndroidKeyStore")
        keyStore.load(null)
        val alias = "device_fingerprint_key"
        if (keyStore.containsAlias(alias)) {
            val entry = keyStore.getEntry(alias, null) as KeyStore.SecretKeyEntry
            return Base64.encodeToString(entry.secretKey.encoded, Base64.NO_WRAP)
        }
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        keyGenerator.init(spec)
        val key = keyGenerator.generateKey()
        return Base64.encodeToString(key.encoded, Base64.NO_WRAP)
    }

    @SuppressLint("MissingPermission")
    private fun getDeviceImei(): String {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                tm.imei ?: "NO_IMEI"
            } else {
                @Suppress("DEPRECATION")
                tm.deviceId ?: "NO_IMEI"
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Cannot get IMEI", e)
            "NO_IMEI"
        }
    }

    private fun getServerPublicKey(): String? {
        return encryptedPrefs.getString(SERVER_PUBLIC_KEY_KEY, null)
    }

    fun setServerPublicKey(publicKey: String) {
        encryptedPrefs.edit().putString(SERVER_PUBLIC_KEY_KEY, publicKey).apply()
        Log.d(TAG, "Server public key stored")
    }

    private fun verifyHmacSignature(data: String, signature: String, publicKey: String): Boolean {
        return try {
            val decodedKey = Base64.decode(publicKey, Base64.NO_WRAP)
            val keySpec = SecretKeySpec(decodedKey, "HmacSHA256")
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(keySpec)
            val expectedSignatureBytes = mac.doFinal(data.toByteArray(StandardCharsets.UTF_8))
            val signatureBytes = Base64.decode(signature, Base64.NO_WRAP)
            MessageDigest.isEqual(expectedSignatureBytes, signatureBytes)
        } catch (e: Exception) {
            Log.e(TAG, "HMAC verification error", e)
            false
        }
    }
}

enum class PautVerificationResult {
    VALID,
    EXPIRED,
    IMEI_MISMATCH,
    INVALID_SIGNATURE,
    ALREADY_USED,
    INVALID_FORMAT,
    MISSING_PUBLIC_KEY,
    ERROR
}

enum class PautExecutionResult {
    EXECUTED,
    NO_TOKEN,
    INVALID_TOKEN,
    TOO_EARLY,
    ERROR
}
