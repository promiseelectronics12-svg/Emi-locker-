package com.emilocker.userapp.security.paut

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.telephony.TelephonyManager
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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
class PadtManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val TAG = "PadtManager"
    private val DATASTORE_NAME = "padt_secure_datastore"
    private val PADT_KEY = "padt_token_encrypted"
    private val SERVER_PUBLIC_KEY_KEY = "server_public_key"
    private val PADT_USED_KEY = "padt_used_"
    private val PADT_USED_VERSION_KEY = "padt_used_version"
    private val PADT_USED_TIMESTAMP_KEY = "padt_used_timestamp_"
    private val PADT_ATTEMPT_COUNTER_KEY = "padt_attempt_counter_"
    private val PADT_RATE_LIMIT_KEY = "padt_rate_limit"
    private val CLOCK_SKEW_TOLERANCE_MS = 45_000L
    private val MAX_VALIDITY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000L
    private val MAX_PADT_ATTEMPTS = 10
    private val RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000L
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

    suspend fun storePadt(jwtToken: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val encrypted = encryptToken(jwtToken)
            encryptedPrefs.edit().putString(PADT_KEY, encrypted).apply()
            Log.d(TAG, "PADT stored successfully")
            Result.success(Unit)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to store PADT", e)
            Result.failure(e)
        }
    }

    suspend fun getStoredPadt(): String? = withContext(Dispatchers.IO) {
        try {
            val encrypted = encryptedPrefs.getString(PADT_KEY, null) ?: return@withContext null
            decryptToken(encrypted)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to retrieve PADT", e)
            null
        }
    }

    suspend fun clearPadt() = withContext(Dispatchers.IO) {
        try {
            encryptedPrefs.edit().remove(PADT_KEY).apply()
            Log.d(TAG, "PADT cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear PADT", e)
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

    suspend fun verifyPadt(token: String, source: String = "UNKNOWN"): PadtVerificationResult = withContext(Dispatchers.IO) {
        try {
            val parts = token.split(".")
            if (parts.size != 5) {
                logAuditFailure("INVALID_FORMAT", "Invalid token structure", source, null)
                Log.w(TAG, "Invalid PADT format: expected 5 parts, got ${parts.size}")
                return@withContext PadtVerificationResult.INVALID_FORMAT
            }

            val deviceImei = parts[0]
            val authorizedAtStr = parts[1]
            val expiresAtStr = parts[2]
            val nonce = parts[3]
            val hmacSig = parts[4]

            val currentDeviceFingerprint = getCompositeDeviceFingerprint()
            if (deviceImei != currentDeviceFingerprint) {
                logAuditFailure("IMEI_MISMATCH", "Device fingerprint mismatch", source, deviceImei)
                Log.w(TAG, "Device fingerprint mismatch: token=$deviceImei, device=$currentDeviceFingerprint")
                return@withContext PadtVerificationResult.IMEI_MISMATCH
            }

            val expiresAt = expiresAtStr.toLongOrNull()
            if (expiresAt == null) {
                logAuditFailure("INVALID_FORMAT", "Invalid expiresAt format", source, deviceImei)
                Log.w(TAG, "Invalid expiresAt format")
                return@withContext PadtVerificationResult.INVALID_FORMAT
            }

            val currentTime = System.currentTimeMillis()
            if (currentTime < expiresAt - CLOCK_SKEW_TOLERANCE_MS) {
                Log.w(TAG, "PADT not yet valid (clock skew tolerance check): expiresAt=$expiresAt, current time: $currentTime")
                return@withContext PadtVerificationResult.EXPIRED
            }
            if (currentTime > expiresAt + CLOCK_SKEW_TOLERANCE_MS) {
                logAuditFailure("EXPIRED", "Token expired", source, deviceImei)
                Log.w(TAG, "PADT expired at $expiresAt, current time: $currentTime")
                return@withContext PadtVerificationResult.EXPIRED
            }

            if (!isNonceValid(nonce, expiresAt)) {
                logAuditFailure("ALREADY_USED", "Nonce already used or invalid", source, deviceImei)
                Log.w(TAG, "PADT already used (nonce: $nonce)")
                return@withContext PadtVerificationResult.ALREADY_USED
            }

            val serverPublicKey = getServerPublicKey()
            if (serverPublicKey == null) {
                Log.e(TAG, "Server public key not available")
                return@withContext PadtVerificationResult.MISSING_PUBLIC_KEY
            }

            val payloadForSig = "$deviceImei|$authorizedAtStr|$expiresAtStr|$nonce"
            val isValidSignature = verifyHmacSignature(payloadForSig, hmacSig, serverPublicKey)

            if (!isValidSignature) {
                logAuditFailure("INVALID_SIGNATURE", "HMAC signature verification failed", source, deviceImei)
                Log.w(TAG, "HMAC signature verification failed")
                return@withContext PadtVerificationResult.INVALID_SIGNATURE
            }

            Log.d(TAG, "PADT verified successfully")
            PadtVerificationResult.VALID
        } catch (e: Exception) {
            Log.e(TAG, "PADT verification error", e)
            PadtVerificationResult.ERROR
        }
    }

    suspend fun checkAndExecutePadt(): PadtExecutionResult = withContext(Dispatchers.IO) {
        val storedPadt = getStoredPadt() ?: return@withContext PadtExecutionResult.NO_TOKEN

        val verificationResult = verifyPadt(storedPadt)
        if (verificationResult != PadtVerificationResult.VALID) {
            Log.w(TAG, "Stored PADT is not valid: $verificationResult")
            return@withContext PadtExecutionResult.INVALID_TOKEN
        }

        try {
            val parts = storedPadt.split(".")
            val authorizedAtStr = parts[1]
            val authorizedAt = authorizedAtStr.toLongOrNull()

            if (authorizedAt == null) {
                return@withContext PadtExecutionResult.INVALID_TOKEN
            }

            val sevenDaysMs = 7 * 24 * 60 * 60 * 1000L
            val currentTime = System.currentTimeMillis()

            if (currentTime < authorizedAt) {
                Log.d(TAG, "PADT not yet authorized. Authorized at: $authorizedAt, current: $currentTime")
                return@withContext PadtExecutionResult.TOO_EARLY
            }

            val nonce = parts[3]

            val attemptCount = encryptedPrefs.getInt(PADT_ATTEMPT_COUNTER_KEY + nonce, 0)
            if (attemptCount >= MAX_PADT_ATTEMPTS) {
                Log.w(TAG, "PADT rate limit exceeded for nonce: $nonce")
                return@withContext PadtExecutionResult.RATE_LIMIT_EXCEEDED
            }

            val rateLimitTimestamp = encryptedPrefs.getLong(PADT_RATE_LIMIT_KEY, 0)
            if (currentTime - rateLimitTimestamp < RATE_LIMIT_WINDOW_MS && attemptCount >= MAX_PADT_ATTEMPTS / 2) {
                Log.w(TAG, "PADT rate limiting active")
                return@withContext PadtExecutionResult.RATE_LIMITED
            }

            markPadtAsUsedWithAtomicOperation(nonce, currentTime)

            Log.d(TAG, "PADT execution authorized and marked as used")
            PadtExecutionResult.EXECUTED
        } catch (e: Exception) {
            Log.e(TAG, "PADT execution error", e)
            PadtExecutionResult.ERROR
        }
    }

    private fun markPadtAsUsedWithAtomicOperation(nonce: String, timestamp: Long) {
        val currentVersion = encryptedPrefs.getInt(PADT_USED_VERSION_KEY, 0)
        val newVersion = currentVersion + 1

        encryptedPrefs.edit()
            .putBoolean(PADT_USED_KEY + nonce, true)
            .putLong(PADT_USED_TIMESTAMP_KEY + nonce, timestamp)
            .putInt(PADT_USED_VERSION_KEY, newVersion)
            .putInt(PADT_ATTEMPT_COUNTER_KEY + nonce,
                encryptedPrefs.getInt(PADT_ATTEMPT_COUNTER_KEY + nonce, 0) + 1)
            .apply()

        Log.d(TAG, "PADT marked as used atomically: nonce=$nonce, version=$newVersion, timestamp=$timestamp")
    }

    suspend fun markPadtAsUsed(nonce: String) = withContext(Dispatchers.IO) {
        try {
            encryptedPrefs.edit()
                .putBoolean(PADT_USED_KEY + nonce, true)
                .putLong(PADT_USED_TIMESTAMP_KEY + nonce, System.currentTimeMillis())
                .apply()
            Log.d(TAG, "PADT marked as used (nonce: $nonce)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mark PADT as used", e)
        }
    }

    suspend fun isPadtUsed(nonce: String): Boolean {
        return try {
            val used = encryptedPrefs.getBoolean(PADT_USED_KEY + nonce, false)
            val timestamp = encryptedPrefs.getLong(PADT_USED_TIMESTAMP_KEY + nonce, 0)

            if (used && timestamp > 0) {
                val version = encryptedPrefs.getInt(PADT_USED_VERSION_KEY, 0)
                Log.d(TAG, "PADT used status: nonce=$nonce, used=$used, timestamp=$timestamp, version=$version")
            }

            used
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check PADT used status", e)
            false
        }
    }

    suspend fun queueServerReport(token: String, action: String) {
        Log.d(TAG, "Queuing server report: action=$action, token=$token")
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

        val alias = "padt_encryption_key"
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

enum class PadtVerificationResult {
    VALID,
    EXPIRED,
    IMEI_MISMATCH,
    INVALID_SIGNATURE,
    ALREADY_USED,
    INVALID_FORMAT,
    MISSING_PUBLIC_KEY,
    ERROR
}

enum class PadtExecutionResult {
    EXECUTED,
    NO_TOKEN,
    INVALID_TOKEN,
    TOO_EARLY,
    RATE_LIMIT_EXCEEDED,
    RATE_LIMITED,
    ERROR
}