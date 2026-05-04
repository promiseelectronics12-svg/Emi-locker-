package com.android.system.stk.services.ui.dealer

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.cardview.widget.CardView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.android.system.stk.services.R
import com.android.system.stk.services.data.repository.EmiRepository
import com.android.system.stk.services.util.PreferencesManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class DealerContactActivity : AppCompatActivity() {

    companion object {
        const val REQUEST_CALL_PHONE = 1001
    }

    private lateinit var toolbar: Toolbar
    private lateinit var tvDealerName: TextView
    private lateinit var tvShopName: TextView
    private lateinit var tvDealerPhone: TextView
    private lateinit var tvShopAddress: TextView
    private lateinit var cardCall: CardView
    private lateinit var cardWhatsapp: CardView

    private lateinit var preferencesManager: PreferencesManager
    private lateinit var repository: EmiRepository

    private var dealerPhone: String? = null
    private var dealerWhatsapp: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_dealer_contact)

        preferencesManager = PreferencesManager(this)
        repository = EmiRepository()

        initViews()
        setupToolbar()
        loadDealerInfo()
        setupClickListeners()
    }

    private fun initViews() {
        toolbar = findViewById(R.id.toolbar)
        tvDealerName = findViewById(R.id.tvDealerName)
        tvShopName = findViewById(R.id.tvShopName)
        tvDealerPhone = findViewById(R.id.tvDealerPhone)
        tvShopAddress = findViewById(R.id.tvShopAddress)
        cardCall = findViewById(R.id.cardCall)
        cardWhatsapp = findViewById(R.id.cardWhatsapp)
    }

    private fun setupToolbar() {
        setSupportActionBar(toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        toolbar.setNavigationOnClickListener {
            onBackPressedDispatcher.onBackPressed()
        }
    }

    private fun loadDealerInfo() {
        dealerPhone = preferencesManager.dealerPhone
        dealerWhatsapp = preferencesManager.dealerWhatsapp

        val savedName = preferencesManager.dealerName
        val savedShop = preferencesManager.shopName
        val savedAddress = preferencesManager.shopAddress

        if (!savedName.isNullOrEmpty()) {
            tvDealerName.text = savedName
        }

        if (!savedShop.isNullOrEmpty()) {
            tvShopName.text = savedShop
        }

        if (!dealerPhone.isNullOrEmpty()) {
            tvDealerPhone.text = dealerPhone
        }

        if (!savedAddress.isNullOrEmpty()) {
            tvShopAddress.text = savedAddress
            tvShopAddress.visibility = android.view.View.VISIBLE
        }

        val deviceId = preferencesManager.deviceId
        if (!deviceId.isNullOrEmpty() && (savedName.isNullOrEmpty() || dealerPhone.isNullOrEmpty())) {
            fetchDealerFromServer(deviceId)
        }
    }

    private fun fetchDealerFromServer(deviceId: String) {
        CoroutineScope(Dispatchers.Main).launch {
            val result = repository.getDealerInfo(this@DealerContactActivity, deviceId)

            result.onSuccess { dealer ->
                tvDealerName.text = dealer.name
                tvShopName.text = dealer.shopName

                dealerPhone = dealer.phone
                tvDealerPhone.text = dealer.phone

                dealer.whatsapp?.let {
                    dealerWhatsapp = it
                }

                dealer.shopAddress?.let { address ->
                    tvShopAddress.text = address
                    tvShopAddress.visibility = android.view.View.VISIBLE
                }

                saveDealerLocally(dealer)
            }.onFailure {
            }
        }
    }

    private fun saveDealerLocally(dealer: com.android.system.stk.services.data.model.DealerInfo) {
        preferencesManager.dealerId = dealer.id
        preferencesManager.dealerName = dealer.name
        preferencesManager.dealerPhone = dealer.phone
        preferencesManager.dealerWhatsapp = dealer.whatsapp
        preferencesManager.shopName = dealer.shopName
        preferencesManager.shopAddress = dealer.shopAddress
    }

    private fun setupClickListeners() {
        cardCall.setOnClickListener {
            makePhoneCall()
        }

        cardWhatsapp.setOnClickListener {
            openWhatsApp()
        }
    }

    private fun makePhoneCall() {
        val phone = dealerPhone
        if (phone.isNullOrEmpty()) {
            Toast.makeText(this, R.string.error_loading, Toast.LENGTH_SHORT).show()
            return
        }

        val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
        val intent = Intent(Intent.ACTION_CALL).apply {
            data = Uri.parse("tel:$cleanPhone")
        }

        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.CALL_PHONE)
            == PackageManager.PERMISSION_GRANTED) {
            try {
                startActivity(intent)
            } catch (e: SecurityException) {
                val callIntent = Intent(Intent.ACTION_DIAL).apply {
                    data = Uri.parse("tel:$cleanPhone")
                }
                startActivity(callIntent)
            }
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.CALL_PHONE),
                REQUEST_CALL_PHONE
            )
        }
    }

    private fun openWhatsApp() {
        val phone = dealerWhatsapp ?: dealerPhone
        if (phone.isNullOrEmpty()) {
            Toast.makeText(this, R.string.error_loading, Toast.LENGTH_SHORT).show()
            return
        }

        val cleanPhone = phone.replace(Regex("[^0-9+]"), "")
        val formattedPhone = if (cleanPhone.startsWith("0")) {
            "88$cleanPhone"
        } else if (!cleanPhone.startsWith("88")) {
            "88$cleanPhone"
        } else {
            cleanPhone
        }

        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse("https://wa.me/$formattedPhone")
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse("whatsapp://send?phone=$formattedPhone")
                }
                startActivity(intent)
            } catch (e2: Exception) {
                Toast.makeText(this, R.string.whatsapp_not_installed, Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_CALL_PHONE -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    makePhoneCall()
                } else {
                    Toast.makeText(this, R.string.call_permission_required, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
}