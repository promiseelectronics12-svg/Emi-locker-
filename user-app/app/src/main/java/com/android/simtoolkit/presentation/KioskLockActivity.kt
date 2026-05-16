package com.android.simtoolkit.presentation

import android.app.ActivityManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.util.Log
import android.view.View
import android.widget.Toast
import android.widget.Button
import android.widget.EditText
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.android.simtoolkit.R
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.databinding.ActivityKioskLockBinding
import com.android.simtoolkit.device.OfflineUnlockApplier
import com.android.simtoolkit.device.OfflineUnlockVerifier
import com.android.simtoolkit.kiosk.AllowedKioskApps
import com.android.simtoolkit.kiosk.KioskApp
import com.android.simtoolkit.model.LockState
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

@AndroidEntryPoint
class KioskLockActivity : AppCompatActivity() {
    private val tag = "KioskLockActivity"
    private lateinit var binding: ActivityKioskLockBinding

    @Inject
    lateinit var preferencesManager: PreferencesManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityKioskLockBinding.inflate(layoutInflater)
        setContentView(binding.root)
        if (intent?.getBooleanExtra(EXTRA_CLOSE_LOCKSCREEN, false) == true) {
            closeLockScreen("close_intent")
            return
        }
        applySystemInsets()
        bindActions()
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                bringLockScreenBack()
            }
        })
    }

    override fun onResume() {
        super.onResume()
        refreshContent()
        ensureLockTask()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_CLOSE_LOCKSCREEN, false)) {
            closeLockScreen("close_intent")
        }
    }

    private fun applySystemInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.kioskRoot) { view, insets ->
            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(0, systemBars.top, 0, systemBars.bottom)
            insets
        }
    }

    private fun bindActions() {
        binding.btnKioskOfflineCode.setOnClickListener { showOfflineUnlockDialog() }
        binding.btnKioskCallDealer.setOnClickListener { dialDealer() }
        binding.btnKioskPhoneApp.setOnClickListener { openPhoneApp() }
    }

    private fun refreshContent() {
        lifecycleScope.launch {
            val state = withContext(Dispatchers.IO) { preferencesManager.getCurrentLockState() }
            val isDecoupled = withContext(Dispatchers.IO) {
                preferencesManager.isDeviceDecoupled.firstOrNull() == true
            }
            if (state == LockState.NORMAL || isDecoupled) {
                closeLockScreen("state=$state decoupled=$isDecoupled")
                return@launch
            }

            val amount = withContext(Dispatchers.IO) { preferencesManager.amountDue.firstOrNull() }
            val days = withContext(Dispatchers.IO) { preferencesManager.daysOverdue.firstOrNull() }
            val dealerName = withContext(Dispatchers.IO) { preferencesManager.dealerName.firstOrNull() }
            val dealerPhone = withContext(Dispatchers.IO) { preferencesManager.dealerPhone.firstOrNull() }

            binding.tvKioskTitle.text = if (state == LockState.FULL_LOCK) {
                "Device Locked"
            } else {
                "Payment Reminder"
            }
            binding.tvKioskSummary.text = if (state == LockState.FULL_LOCK) {
                "Payment is overdue. You can still call your dealer, enter an offline unlock code, and open approved payment apps."
            } else {
                "Payment is due. Please use an approved payment app or contact your dealer."
            }
            binding.tvKioskAmount.text = buildString {
                append("Amount due: ")
                append(amount?.takeIf { it.isNotBlank() } ?: "--")
                if (days != null && days > 0) append(" - $days day(s) overdue")
            }
            binding.tvKioskDealer.text = buildString {
                append("Dealer: ")
                append(dealerName?.takeIf { it.isNotBlank() } ?: "--")
                dealerPhone?.takeIf { it.isNotBlank() }?.let { append(" - $it") }
            }
            binding.btnKioskCallDealer.isEnabled = !dealerPhone.isNullOrBlank()
            renderAllowedApps(AllowedKioskApps.installedLaunchableApps(this@KioskLockActivity))
        }
    }

    private fun renderAllowedApps(apps: List<KioskApp>) {
        binding.paymentAppContainer.removeAllViews()
        binding.tvNoPaymentApps.visibility = if (apps.isEmpty()) View.VISIBLE else View.GONE

        apps.forEach { app ->
            val button = Button(this).apply {
                text = app.label
                isAllCaps = false
                setTextColor(ContextCompat.getColor(this@KioskLockActivity, R.color.error))
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                backgroundTintList = android.content.res.ColorStateList.valueOf(
                    ContextCompat.getColor(this@KioskLockActivity, R.color.white)
                )
                setOnClickListener { launchAllowedApp(app) }
            }
            val params = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                resources.getDimensionPixelSize(R.dimen.kiosk_button_height)
            ).apply {
                topMargin = resources.getDimensionPixelSize(R.dimen.kiosk_button_gap)
            }
            binding.paymentAppContainer.addView(button, params)
        }
    }

    private fun dialDealer() {
        lifecycleScope.launch {
            val phone = withContext(Dispatchers.IO) { preferencesManager.dealerPhone.firstOrNull() }
            if (!phone.isNullOrBlank()) dialNumber(phone)
        }
    }

    private fun showOfflineUnlockDialog() {
        val input = EditText(this).apply {
            hint = "6-digit code"
            inputType = InputType.TYPE_CLASS_NUMBER
            filters = arrayOf(InputFilter.LengthFilter(6))
            setSingleLine(true)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle("Offline unlock")
            .setMessage("Enter the 6-digit code from your dealer.")
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Unlock", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                verifyOfflineUnlock(input.text?.toString().orEmpty(), dialog)
            }
        }
        dialog.show()
    }

    private fun verifyOfflineUnlock(code: String, dialog: AlertDialog) {
        lifecycleScope.launch {
            val secret = withContext(Dispatchers.IO) {
                preferencesManager.offlineUnlockSecret.firstOrNull()
            }
            val graceHours = secret?.let { OfflineUnlockVerifier.verify(code, it) }
            if (graceHours == null) {
                Toast.makeText(
                    this@KioskLockActivity,
                    "Invalid or expired unlock code",
                    Toast.LENGTH_SHORT
                ).show()
                return@launch
            }

            Toast.makeText(
                this@KioskLockActivity,
                "Unlocked for $graceHours hours",
                Toast.LENGTH_SHORT
            ).show()
            OfflineUnlockApplier.unlockForGrace(this@KioskLockActivity, graceHours, "KIOSK_MANUAL_OTP")
            dialog.dismiss()
        }
    }

    private fun openPhoneApp() {
        startExternalIntent(Intent(Intent.ACTION_DIAL))
    }

    private fun dialNumber(number: String) {
        startExternalIntent(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))
    }

    private fun launchAllowedApp(app: KioskApp) {
        val intent = packageManager.getLaunchIntentForPackage(app.packageName)
        if (intent == null) {
            refreshContent()
            return
        }
        startExternalIntent(intent)
    }

    private fun startExternalIntent(intent: Intent) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(tag, "Unable to open approved action: ${e.message}")
        }
    }

    private fun ensureLockTask() {
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
                startLockTask()
            }
        } catch (e: Exception) {
            Log.w(tag, "Unable to start lock task: ${e.message}")
        }
    }

    private fun stopLockTaskIfNeeded() {
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            if (am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
                stopLockTask()
            }
        } catch (e: Exception) {
            Log.w(tag, "Unable to stop lock task: ${e.message}")
        }
    }

    private fun bringLockScreenBack() {
        val intent = Intent(this, KioskLockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun closeLockScreen(reason: String) {
        Log.d(tag, "Closing kiosk lock screen: $reason")
        stopLockTaskIfNeeded()
        try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(homeIntent)
        } catch (e: Exception) {
            Log.w(tag, "Unable to return to home while closing kiosk: ${e.message}")
        }
        finishAndRemoveTask()
    }

    companion object {
        const val EXTRA_CLOSE_LOCKSCREEN = "extra_close_lockscreen"
    }
}
