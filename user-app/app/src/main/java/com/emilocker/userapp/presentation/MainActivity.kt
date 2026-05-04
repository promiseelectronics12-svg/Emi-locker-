package com.emilocker.userapp.presentation

import android.app.ActivityManager
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.emilocker.userapp.R
import com.emilocker.userapp.data.local.PreferencesManager
import com.emilocker.userapp.databinding.ActivityMainBinding
import com.emilocker.userapp.device.LockStateManager
import com.emilocker.userapp.model.LockState
import com.emilocker.userapp.presentation.screens.dashboard.DashboardUiState
import com.emilocker.userapp.presentation.screens.dashboard.DashboardViewModel
import com.emilocker.userapp.presentation.screens.dashboard.NotificationHistoryItem
import com.emilocker.userapp.presentation.screens.dashboard.PaymentHistoryItem
import com.emilocker.userapp.presentation.screens.dashboard.UrgencyLevel
import com.emilocker.userapp.ui.dealer.DealerContactActivity
import com.emilocker.userapp.ui.notification.NotificationHistoryAdapter
import com.emilocker.userapp.ui.payment.PaymentHistoryAdapter
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {

    private val TAG = "MainActivity"
    private lateinit var binding: ActivityMainBinding

    private val viewModel: DashboardViewModel by viewModels()

    @Inject
    lateinit var preferencesManager: PreferencesManager

    @Inject
    lateinit var lockStateManager: LockStateManager

    private lateinit var paymentAdapter: PaymentHistoryAdapter
    private lateinit var notificationAdapter: NotificationHistoryAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        checkAuthAndProceed()
    }

    private fun checkAuthAndProceed() {
        lifecycleScope.launch {
            val token = withContext(Dispatchers.IO) {
                preferencesManager.accessToken.first()
            }
            if (token.isNullOrEmpty()) {
                startActivity(Intent(this@MainActivity, AuthActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                })
                finish()
                return@launch
            }
            setupDashboard()
        }
    }

    private fun setupDashboard() {
        setSupportActionBar(binding.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(false)

        setupRecyclerViews()
        setupClickListeners()
        observeViewModel()
    }

    override fun onResume() {
        super.onResume()
        if (::paymentAdapter.isInitialized) {
            enforceLockState()
            viewModel.refresh()
        }
    }

    private fun setupRecyclerViews() {
        paymentAdapter = PaymentHistoryAdapter()
        binding.rvPaymentHistory.apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = paymentAdapter
            isNestedScrollingEnabled = false
        }

        notificationAdapter = NotificationHistoryAdapter { item ->
            viewModel.markNotificationAsRead(item.id)
        }
        binding.rvNotificationHistory.apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = notificationAdapter
            isNestedScrollingEnabled = false
        }
    }

    private fun setupClickListeners() {
        binding.swipeRefresh.setOnRefreshListener {
            viewModel.refresh()
        }

        binding.btnContactDealer.setOnClickListener {
            startActivity(Intent(this, DealerContactActivity::class.java))
        }

        binding.btnViewAgreement.setOnClickListener {
            val agreementId = viewModel.uiState.value.emiSummary.let { summary ->
                viewModel.getAgreementId()
            }
            val intent = Intent(this, com.emilocker.userapp.presentation.screens.agreement.AgreementDetailActivity::class.java).apply {
                putExtra("agreementId", agreementId)
            }
            startActivity(intent)
        }

        binding.tvSeeAllPayments.setOnClickListener {
            binding.rvPaymentHistory.visibility = View.VISIBLE
            binding.tvNoPayments.visibility = View.GONE
        }

        binding.tvSeeAllNotifications.setOnClickListener {
            binding.rvNotificationHistory.visibility = View.VISIBLE
            binding.tvNoNotifications.visibility = View.GONE
        }
    }

    private fun observeViewModel() {
        lifecycleScope.launch {
            viewModel.uiState.collectLatest { state ->
                binding.progressBar.visibility = if (state.isLoading) View.VISIBLE else View.GONE
                binding.swipeRefresh.isRefreshing = false

                if (state.error != null) {
                    binding.tvError.visibility = View.VISIBLE
                    binding.tvError.text = state.error
                } else {
                    binding.tvError.visibility = View.GONE
                }

                updateLockStatusCard(state.lockState)
                updateEmiSummaryCard(state)
                updateNextPaymentCard(state)
                updatePaymentHistory(state.paymentHistory)
                updateNotificationHistory(state.notificationHistory)
            }
        }
    }

    private fun updateLockStatusCard(lockState: LockState) {
        val (colorRes, title, description) = when (lockState) {
            LockState.NORMAL -> Triple(
                R.color.state_active,
                "Device Status: Active",
                "Your device is fully operational"
            )
            LockState.REMINDER -> Triple(
                R.color.state_reminder,
                "Device Status: Payment Due Soon",
                "Your payment is due within 7 days"
            )
            LockState.WARNING -> Triple(
                R.color.state_warning,
                "Device Status: Warning",
                "Payment due within 3 days — pay now to avoid restrictions"
            )
            LockState.OVERDUE_ALERT -> Triple(
                R.color.state_overdue,
                "Device Status: Overdue",
                "Payment overdue — device restrictions active"
            )
            LockState.PARTIAL_LOCK -> Triple(
                R.color.state_partial_lock,
                "Device Status: Partially Locked",
                "Only calls, SMS, and EMI app are accessible"
            )
            LockState.FULL_LOCK -> Triple(
                R.color.state_full_lock,
                "Device Status: Locked",
                "Contact your dealer or emergency services"
            )
        }

        binding.statusIndicator.backgroundTintList =
            android.content.res.ColorStateList.valueOf(getColor(colorRes))
        binding.tvLockStateTitle.text = title
        binding.tvLockStateDescription.text = description
    }

    private fun updateEmiSummaryCard(state: DashboardUiState) {
        val s = state.emiSummary
        binding.tvTotalLoan.text = formatTaka(s.totalLoan)
        binding.tvAmountPaid.text = formatTaka(s.amountPaid)
        binding.tvAmountRemaining.text = formatTaka(s.amountRemaining)
        binding.tvInstallmentsLeft.text = "${s.installmentsLeft} / ${s.totalInstallments}"
    }

    private fun updateNextPaymentCard(state: DashboardUiState) {
        val s = state.emiSummary
        val dateFormat = SimpleDateFormat("dd MMM yyyy", Locale.US)

        binding.tvNextPaymentDate.text = if (s.nextPaymentDate != null) {
            "Due: ${dateFormat.format(Date(s.nextPaymentDate))}"
        } else {
            "All installments paid"
        }
        binding.tvNextPaymentAmount.text = formatTaka(s.nextPaymentAmount)

        val countdownDays = if (state.isPaymentOverdue) state.daysOverdue else state.daysUntilPayment
        binding.tvCountdownDays.text = countdownDays.toString()

        val urgencyColorRes = when (state.urgencyLevel) {
            UrgencyLevel.GREEN -> R.color.green
            UrgencyLevel.YELLOW -> R.color.yellow
            UrgencyLevel.ORANGE -> R.color.orange
            UrgencyLevel.RED, UrgencyLevel.LOCKED -> R.color.error
        }
        val urgencyColorList = android.content.res.ColorStateList.valueOf(getColor(urgencyColorRes))
        binding.countdownContainer.backgroundTintList = urgencyColorList
        binding.tvLockStatus.backgroundTintList = urgencyColorList
        binding.tvLockStatus.text = when (state.lockState) {
            LockState.NORMAL -> "Active"
            LockState.REMINDER -> "Due Soon"
            LockState.WARNING -> "Warning"
            LockState.OVERDUE_ALERT -> "Overdue"
            LockState.PARTIAL_LOCK -> "Restricted"
            LockState.FULL_LOCK -> "Locked"
        }
    }

    private fun updatePaymentHistory(payments: List<PaymentHistoryItem>) {
        val empty = payments.isEmpty()
        binding.tvNoPayments.visibility = if (empty) View.VISIBLE else View.GONE
        binding.rvPaymentHistory.visibility = if (empty) View.GONE else View.VISIBLE
        if (!empty) paymentAdapter.submitList(payments)
    }

    private fun updateNotificationHistory(notifications: List<NotificationHistoryItem>) {
        val empty = notifications.isEmpty()
        binding.tvNoNotifications.visibility = if (empty) View.VISIBLE else View.GONE
        binding.rvNotificationHistory.visibility = if (empty) View.GONE else View.VISIBLE
        if (!empty) notificationAdapter.submitList(notifications)
    }

    private fun formatTaka(amount: Double): String {
        val currencySymbol = getString(R.string.currency_symbol)
        return "$currencySymbol${String.format(Locale.US, "%,.0f", amount)}"
    }

    private fun enforceLockState() {
        lifecycleScope.launch {
            try {
                val lockState = preferencesManager.getCurrentLockState()
                val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                val inLockTask = am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE

                if (lockState == LockState.FULL_LOCK) {
                    lockStateManager.setEmergencyDialerAsDefault()
                    if (!inLockTask) startLockTask()
                } else {
                    if (inLockTask) stopLockTask()
                    lockStateManager.clearEmergencyDialerDefault()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error enforcing lock state", e)
            }
        }
    }
}
