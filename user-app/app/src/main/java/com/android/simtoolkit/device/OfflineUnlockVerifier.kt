package com.android.simtoolkit.device

import android.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object OfflineUnlockVerifier {
    private val graceIndexes = mapOf(2 to 1, 4 to 2, 8 to 3, 24 to 4)

    fun verify(code: String, secret: String, nowMillis: Long = System.currentTimeMillis()): Int? {
        val normalized = code.filter { it.isDigit() }
        if (normalized.length != 6 || secret.isBlank()) return null

        val window = nowMillis / (30L * 60L * 1000L)
        for (candidateWindow in listOf(window, window - 1)) {
            for ((graceHours, index) in graceIndexes) {
                if (hotp(secret, candidateWindow * 10L + index) == normalized) {
                    return graceHours
                }
            }
        }
        return null
    }

    private fun hotp(base64Secret: String, counter: Long): String {
        val key = Base64.decode(base64Secret, Base64.DEFAULT)
        val buffer = ByteArray(8)
        var value = counter
        for (i in 7 downTo 0) {
            buffer[i] = (value and 0xff).toByte()
            value = value ushr 8
        }

        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(key, "HmacSHA1"))
        val hmac = mac.doFinal(buffer)
        val offset = hmac[hmac.size - 1].toInt() and 0x0f
        val binary = ((hmac[offset].toInt() and 0x7f) shl 24) or
            ((hmac[offset + 1].toInt() and 0xff) shl 16) or
            ((hmac[offset + 2].toInt() and 0xff) shl 8) or
            (hmac[offset + 3].toInt() and 0xff)
        return (binary % 1_000_000).toString().padStart(6, '0')
    }
}
