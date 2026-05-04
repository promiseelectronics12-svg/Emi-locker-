package com.emilocker.userapp.ui.dealer

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.telephony.TelephonyManager
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.emilocker.userapp.data.local.PreferencesManager
import com.emilocker.userapp.databinding.ActivityDealerContactBinding
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class DealerContactActivity : AppCompatActivity() {

    private lateinit var binding: ActivityDealerContactBinding

    @Inject
    lateinit var preferencesManager: PreferencesManager

    private var dealerPhone: String = ""
    private var dealerWhatsApp: String = ""
    private var countryCode: String = ""

    companion object {
        private const val REQUEST_CALL_PERMISSION = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityDealerContactBinding.inflate(layoutInflater)
        setContentView(binding.root)

        detectCountryCode()
        loadDealerInfo()
        setupClickListeners()
    }

    private fun detectCountryCode(): String {
        countryCode = try {
            val telecomManager = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            val simCountry = telecomManager?.simCountryIso
            if (!simCountry.isNullOrBlank()) {
                when (simCountry.uppercase()) {
                    "BD" -> "880"
                    "IN" -> "91"
                    "US" -> "1"
                    "GB" -> "44"
                    else -> getNumericCodeForCountry(simCountry)
                }
            } else {
                val locale = resources.configuration.locales[0]
                if (!locale.country.isNullOrBlank()) {
                    getNumericCodeForCountry(locale.country)
                } else {
                    "880"
                }
            }
        } catch (e: Exception) {
            "880"
        }
    }

    private fun getNumericCodeForCountry(countryCode: String): String {
        return when (countryCode.uppercase()) {
            "BD", "BGD" -> "880"
            "IN", "IND" -> "91"
            "US", "USA" -> "1"
            "GB", "GBR" -> "44"
            "PK", "PAK" -> "92"
            "ID", "IDN" -> "62"
            "MY", "MYS" -> "60"
            "TH", "THA" -> "66"
            "VN", "VNM" -> "84"
            "PH", "PHL" -> "63"
            "NP", "NPL" -> "977"
            "LK", "LKA" -> "94"
            else -> "880"
        }
    }

    private fun loadDealerInfo() {
        lifecycleScope.launch {
            try {
                val name = preferencesManager.dealerName.first() ?: "Unknown Dealer"
                val phone = preferencesManager.dealerPhone.first() ?: ""

                dealerPhone = phone
                dealerWhatsApp = phone.replace("[^0-9+]".toRegex(), "")

                binding.tvDealerName.text = name
                binding.tvDealerPhone.text = if (phone.isNotEmpty()) formatPhoneNumber(phone) else "No phone available"

                updateCallButtonState(phone.isNotEmpty())
                updateWhatsAppButtonState(dealerWhatsApp.isNotEmpty())
            } catch (e: Exception) {
                binding.tvDealerName.text = "Dealer Information Unavailable"
                binding.tvDealerPhone.text = "Please contact support"
                updateCallButtonState(false)
                updateWhatsAppButtonState(false)
            }
        }
    }

    private fun setupClickListeners() {
        binding.btnCall.setOnClickListener {
            initiateCall()
        }

        binding.btnWhatsapp.setOnClickListener {
            initiateWhatsApp()
        }

        binding.toolbar.setNavigationOnClickListener {
            finish()
        }
    }

    private fun initiateCall() {
        if (dealerPhone.isEmpty()) {
            Toast.makeText(this, "Phone number not available", Toast.LENGTH_SHORT).show()
            return
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            == PackageManager.PERMISSION_GRANTED
        ) {
            val callIntent = Intent(Intent.ACTION_CALL).apply {
                data = Uri.parse("tel:$dealerPhone")
            }
            try {
                startActivity(callIntent)
            } catch (e: Exception) {
                val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse("tel:$dealerPhone")
                }
                startActivity(dialIntent)
            }
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CALL_PHONE),
                REQUEST_CALL_PERMISSION
            )
        }
    }

    private fun initiateWhatsApp() {
        if (dealerWhatsApp.isEmpty()) {
            Toast.makeText(this, "WhatsApp number not available", Toast.LENGTH_SHORT).show()
            return
        }

        try {
            val formattedNumber = if (dealerWhatsApp.startsWith("0")) {
                "+$countryCode$dealerWhatsApp"
            } else if (!dealerWhatsApp.startsWith("+")) {
                "+$countryCode$dealerWhatsApp"
            } else {
                dealerWhatsApp
            }

            val whatsappIntent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://wa.me/$formattedNumber")
            }
            startActivity(whatsappIntent)
        } catch (e: Exception) {
            val webIntent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://wa.me/${dealerWhatsApp.replace("+", "")}")
            }
            try {
                startActivity(webIntent)
            } catch (e2: Exception) {
                Toast.makeText(this, "WhatsApp not installed", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun updateCallButtonState(enabled: Boolean) {
        binding.btnCall.isEnabled = enabled
        binding.btnCall.alpha = if (enabled) 1.0f else 0.5f
    }

    private fun updateWhatsAppButtonState(enabled: Boolean) {
        binding.btnWhatsapp.isEnabled = enabled
        binding.btnWhatsapp.alpha = if (enabled) 1.0f else 0.5f
    }

    private fun formatPhoneNumber(phone: String): String {
        return if (phone.length == 11 && phone.startsWith("01")) {
            "+$countryCode$phone"
        } else {
            phone
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_CALL_PERMISSION -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    initiateCall()
                } else {
                    val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                        data = Uri.parse("tel:$dealerPhone")
                    }
                    startActivity(dialIntent)
                }
            }
        }
    }
}