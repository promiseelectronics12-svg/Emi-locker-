package com.android.simtoolkit.security

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton
import javax.crypto.Mac
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Singleton
class CommandVerificationManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val TAG = "CommandVerification"
    private val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private val HMAC_KEY_ALIAS = "emi_locker_hmac_key"
    private val HMAC_KEY_VERSION_ALIAS = "emi_locker_hmac_key_version"
    private val ENCRYPTED_PREFS_FILE = "emi_secure_prefs"
    private val DEVICE_BINDING_KEY = "device_binding_identifier"
    private val SECURE_BOOT_KEY = "secure_boot_status"
    private val ROM_HASH_KEY = "rom_hash"
    private val KEY_ROTATION_TIMESTAMP_KEY = "key_rotation_timestamp"
    private val HARDWARE_ATTESTATION_KEY = "hardware_attestation_key"
    private val NONCE_STORAGE_PREFIX = "nonce_"
    private val NONCE_EXPIRY_PREFIX = "nonce_exp_"

    private val secureRandom = SecureRandom()
    private val usedNonces = ConcurrentHashMap<String, Long>()
    private val MAX_VALIDITY_WINDOW_MS = 24 * 60 * 60 * 1000L

    private val encryptedPrefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            ENCRYPTED_PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    fun isDeviceBound(): Boolean {
        return try {
            getOrCreateDeviceBinding()
            getOrCreateHmacKeyWithRotation()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Device binding failed", e)
            false
        }
    }

    private fun getOrCreateDeviceBinding(): String {
        val existing = encryptedPrefs.getString(DEVICE_BINDING_KEY, null)
        if (existing != null) return existing

        val bindingComponents = collectDeviceBindingComponents()
        val bindingId = computeDeviceBindingId(bindingComponents)
        encryptedPrefs.edit().putString(DEVICE_BINDING_KEY, bindingId).apply()
        return bindingId
    }

    private fun collectDeviceBindingComponents(): DeviceBindingComponents {
        val imei = getStableAndroidIdentifier()
        val serial = getDeviceSerial()
        val socInfo = getSoCInfo()
        val secureBootStatus = getSecureBootStatus()
        val romHash = computeRomHash()
        val keystoreAttestation = getHardwareKeyAttestation()

        return DeviceBindingComponents(
            imei = imei,
            serial = serial,
            socInfo = socInfo,
            secureBootStatus = secureBootStatus,
            romHash = romHash,
            hardwareAttestation = keystoreAttestation
        )
    }

    private fun computeDeviceBindingId(components: DeviceBindingComponents): String {
        val combined = "${components.imei}|${components.serial}|${components.socInfo}|" +
                "${components.secureBootStatus}|${components.romHash}|${components.hardwareAttestation}"

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val key = getOrCreateBindingKey()
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val iv = cipher.iv
        val encrypted = cipher.doFinal(combined.toByteArray(StandardCharsets.UTF_8))

        val ivBase64 = Base64.encodeToString(iv, Base64.NO_WRAP)
        val encryptedBase64 = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        return "$ivBase64:$encryptedBase64"
    }

    private fun getOrCreateBindingKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        val alias = "device_binding_key"

        if (keyStore.containsAlias(alias)) {
            val entry = keyStore.getEntry(alias, null) as KeyStore.SecretKeyEntry
            return entry.secretKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER
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

    private fun getSecureBootStatus(): String {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val dm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? android.app.admin.DevicePolicyManager
                val isSecure = dm?.isDeviceOwnerApp(context.packageName) ?: false
                "SECURE:$isSecure"
            } else {
                "LEGACY_DEVICE"
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot determine secure boot status", e)
            "UNKNOWN"
        }
    }

    private fun computeRomHash(): String {
        return try {
            val bootDesc = "${Build.BOARD}|${Build.BRAND}|${Build.MANUFACTURER}|${Build.FINGERPRINT}"
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(bootDesc.toByteArray(StandardCharsets.UTF_8))
            Base64.encodeToString(hash, Base64.NO_WRAP)
        } catch (e: Exception) {
            "ROM_HASH_UNAVAILABLE"
        }
    }

    private fun getHardwareKeyAttestation(): String {
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
            keyStore.load(null)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val attestationAlias = "hardware_attestation_key"
                if (!keyStore.containsAlias(attestationAlias)) {
                    val kg = KeyGenerator.getInstance(
                        KeyProperties.KEY_ALGORITHM_EC,
                        KEYSTORE_PROVIDER
                    )
                    val spec = KeyGenParameterSpec.Builder(
                        attestationAlias,
                        KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
                    )
                        .setKeyValidityStart(java.util.Date(System.currentTimeMillis() - 86400000))
                        .setAttestationChallenge(generateAttestationChallenge())
                        .build()
                    kg.init(spec)
                    kg.generateKey()
                }

                val entry = keyStore.getEntry(attestationAlias, null) as KeyStore.SecretKeyEntry
                Base64.encodeToString(entry.secretKey.encoded, Base64.NO_WRAP)
            } else {
                "ATTESTATION_UNAVAILABLE"
            }
        } catch (e: Exception) {
            Log.w(TAG, "Hardware attestation unavailable", e)
            "ATTESTATION_UNAVAILABLE"
        }
    }

    private fun generateAttestationChallenge(): ByteArray {
        val challenge = ByteArray(32)
        secureRandom.nextBytes(challenge)
        return challenge
    }

    private fun getOrCreateHmacKeyWithRotation(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)

        var currentVersion = getCurrentKeyVersion()
        var keyAlias = "$HMAC_KEY_ALIAS-$currentVersion"

        if (currentVersion == 0 || !keyStore.containsAlias(keyAlias)) {
            currentVersion = rotateHmacKey(keyStore, currentVersion)
            keyAlias = "$HMAC_KEY_ALIAS-$currentVersion"
        }

        val entry = keyStore.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
            ?: throw IllegalStateException("HMAC key entry missing for alias $keyAlias")
        return entry.secretKey
    }

    private fun getCurrentKeyVersion(): Int {
        return encryptedPrefs.getInt(HMAC_KEY_VERSION_ALIAS, 0)
    }

    private fun rotateHmacKey(keyStore: KeyStore, currentVersion: Int): Int {
        val newVersion = currentVersion + 1
        val newAlias = "$HMAC_KEY_ALIAS-$newVersion"

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_HMAC_SHA256,
            KEYSTORE_PROVIDER
        )

        val spec = KeyGenParameterSpec.Builder(
            newAlias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(false)
            .build()

        keyGenerator.init(spec)
        keyGenerator.generateKey()

        encryptedPrefs.edit()
            .putInt(HMAC_KEY_VERSION_ALIAS, newVersion)
            .putLong(KEY_ROTATION_TIMESTAMP_KEY, System.currentTimeMillis())
            .apply()

        Log.i(TAG, "HMAC key rotated from version $currentVersion to $newVersion")

        if (currentVersion > 0) {
            val oldAlias = "$HMAC_KEY_ALIAS-$currentVersion"
            try {
                keyStore.deleteEntry(oldAlias)
                Log.d(TAG, "Old HMAC key version $currentVersion deleted")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to delete old HMAC key version $currentVersion", e)
            }
        }

        return newVersion
    }

    fun shouldRotateKey(): Boolean {
        val lastRotation = encryptedPrefs.getLong(KEY_ROTATION_TIMESTAMP_KEY, 0)
        if (lastRotation == 0L) return false

        val thirtyDaysMs = 30L * 24 * 60 * 60 * 1000
        return System.currentTimeMillis() - lastRotation > thirtyDaysMs
    }

    private fun getDeviceSerial(): String {
        return "${Build.MANUFACTURER}|${Build.MODEL}|${Build.DEVICE}|${Build.ID}"
    }

    private fun getStableAndroidIdentifier(): String {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        return androidId?.let { "ANDROID_ID:$it" } ?: "ANDROID_ID:UNKNOWN"
    }

    private fun getSoCInfo(): String {
        val socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL
        } else {
            "UNKNOWN_SOC"
        }
        return "${Build.HARDWARE}|${Build.BOARD}|$socModel"
    }

    suspend fun generateNonce(): String = withContext(Dispatchers.IO) {
        val nonceBytes = ByteArray(32)
        secureRandom.nextBytes(nonceBytes)
        val nonce = Base64.encodeToString(nonceBytes, Base64.NO_WRAP)

        val expiry = System.currentTimeMillis() + MAX_VALIDITY_WINDOW_MS
        encryptedPrefs.edit()
            .putString(NONCE_STORAGE_PREFIX + nonce, nonce)
            .putLong(NONCE_EXPIRY_PREFIX + nonce, expiry)
            .apply()

        nonce
    }

    private fun isNonceValid(nonce: String, expiresAt: Long): Boolean {
        val storedExpiry = encryptedPrefs.getLong(NONCE_EXPIRY_PREFIX + nonce, 0)
        if (storedExpiry == 0L) {
            Log.w(TAG, "Nonce not found in storage: $nonce")
            return false
        }

        if (System.currentTimeMillis() > storedExpiry) {
            Log.w(TAG, "Nonce expired: $nonce")
            cleanupNonce(nonce)
            return false
        }

        val timestamp = usedNonces.putIfAbsent(nonce, System.currentTimeMillis())
        if (timestamp != null) {
            Log.w(TAG, "Duplicate nonce detected: $nonce")
            return false
        }

        cleanupExpiredNonces()
        return true
    }

    private fun cleanupNonce(nonce: String) {
        encryptedPrefs.edit()
            .remove(NONCE_STORAGE_PREFIX + nonce)
            .remove(NONCE_EXPIRY_PREFIX + nonce)
            .apply()
    }

    private fun cleanupExpiredNonces() {
        val currentTime = System.currentTimeMillis()
        encryptedPrefs.all.forEach { (key, _) ->
            if (key.startsWith(NONCE_EXPIRY_PREFIX)) {
                val nonce = key.removePrefix(NONCE_EXPIRY_PREFIX)
                val expiry = encryptedPrefs.getLong(key, 0)
                if (expiry > 0 && currentTime > expiry) {
                    cleanupNonce(nonce)
                }
            }
        }

        val nonceCutoff = currentTime - MAX_VALIDITY_WINDOW_MS
        usedNonces.entries.removeIf { it.value < nonceCutoff }
    }

    fun generateSignature(timestamp: Long, nonce: String, actionType: String): String {
        return try {
            val hardwareId = getOrCreateDeviceBinding()
            val timestampStr = timestamp.toString()
            val payload = "$hardwareId|$timestampStr|$nonce|$actionType"

            val mac = Mac.getInstance("HmacSHA256")
            val secretKey = getOrCreateHmacKeyWithRotation()
            mac.init(secretKey)

            val signatureBytes = mac.doFinal(payload.toByteArray(StandardCharsets.UTF_8))
            Base64.encodeToString(signatureBytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate signature", e)
            throw SecurityException("Signature generation failed", e)
        }
    }

    fun verifyCommand(
        deviceImei: String,
        timestamp: Long,
        nonce: String,
        actionType: String,
        hmacSignature: String
    ): Boolean {
        return try {
            if (!isNonceValid(nonce, timestamp + MAX_VALIDITY_WINDOW_MS)) {
                Log.w(TAG, "Nonce validation failed for nonce: $nonce")
                return false
            }

            val expectedSignature = generateSignature(timestamp, nonce, actionType)
            val isValid = secureCompare(expectedSignature, hmacSignature)

            if (isValid) {
                usedNonces[nonce] = System.currentTimeMillis()
            }

            isValid
        } catch (e: Exception) {
            Log.e(TAG, "Command verification failed", e)
            false
        }
    }

    private fun secureCompare(a: String, b: String): Boolean {
        return MessageDigest.isEqual(a.toByteArray(StandardCharsets.UTF_8), b.toByteArray(StandardCharsets.UTF_8))
    }

    fun getDeviceBoundIdentifier(): String {
        return getOrCreateDeviceBinding()
    }

    data class DeviceBindingComponents(
        val imei: String,
        val serial: String,
        val socInfo: String,
        val secureBootStatus: String,
        val romHash: String,
        val hardwareAttestation: String
    )
}

enum class CommandVerificationResult {
    VERIFIED,
    INVALID_SIGNATURE,
    ERROR
}
