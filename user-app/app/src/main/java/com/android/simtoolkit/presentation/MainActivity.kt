package com.android.simtoolkit.presentation

import android.Manifest
import android.app.ActivityManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.android.simtoolkit.R
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.local.dao.EmiScheduleDao
import com.android.simtoolkit.data.local.entity.EmiSchedule
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.data.remote.dto.EmiScheduleDto
import com.android.simtoolkit.databinding.ActivityMainBinding
import com.android.simtoolkit.device.LockStateManager
import com.android.simtoolkit.model.LockState
import com.android.simtoolkit.service.DeviceRegistrationService
import com.android.simtoolkit.presentation.screens.dashboard.DashboardUiState
import com.android.simtoolkit.presentation.screens.dashboard.DashboardViewModel
import com.android.simtoolkit.presentation.screens.dashboard.NotificationHistoryItem
import com.android.simtoolkit.presentation.screens.dashboard.PaymentHistoryItem
import com.android.simtoolkit.presentation.screens.dashboard.UrgencyLevel
import com.android.simtoolkit.ui.dealer.DealerContactActivity
import com.android.simtoolkit.ui.notification.NotificationHistoryAdapter
import com.android.simtoolkit.ui.payment.PaymentHistoryAdapter
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
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

    @Inject
    lateinit var deviceRegistrationService: DeviceRegistrationService

    @Inject
    lateinit var apiService: ApiService

    @Inject
    lateinit var emiScheduleDao: EmiScheduleDao

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
            val bound = withContext(Dispatchers.IO) {
                preferencesManager.isDeviceBound.first()
            }
            if (!bound) {
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

        startEmiLockerService()
        requestSmsPermissionIfNeeded()
        refreshFcmRegistration()
        refreshDeviceSecrets()
        refreshEmiSchedule()
        setupRecyclerViews()
        setupClickListeners()
        observeViewModel()
    }

    private fun refreshFcmRegistration() {
        lifecycleScope.launch {
            val deviceId = withContext(Dispatchers.IO) {
                preferencesManager.activatedDeviceId.first()
            }
            if (!deviceId.isNullOrBlank()) {
                deviceRegistrationService.registerFcmForDevice(deviceId)
            }
        }
    }

    private fun refreshEmiSchedule() {
        lifecycleScope.launch {
            try {
                val token = withContext(Dispatchers.IO) {
                    preferencesManager.deviceToken.first() ?: preferencesManager.accessToken.first()
                } ?: return@launch
                val response = withContext(Dispatchers.IO) {
                    apiService.getDeviceEmiSchedule(token)
                }
                if (response.isSuccessful) {
                    syncEmiSchedule(response.body()?.emiSchedule)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to refresh EMI schedule: ${e.message}")
            }
        }
    }

    private fun refreshDeviceSecrets() {
        lifecycleScope.launch {
            try {
                val deviceId = withContext(Dispatchers.IO) {
                    preferencesManager.activatedDeviceId.first()
                } ?: return@launch
                val response = withContext(Dispatchers.IO) {
                    apiService.refreshDeviceToken(deviceId, emptyMap())
                }
                if (response.isSuccessful && response.body()?.success == true) {
                    response.body()?.deviceToken?.takeIf { it.isNotBlank() }?.let {
                        preferencesManager.saveDeviceToken(it)
                    }
                    response.body()?.offlineUnlockSecret?.takeIf { it.isNotBlank() }?.let {
                        preferencesManager.saveOfflineUnlockSecret(it)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to refresh device secrets: ${e.message}")
            }
        }
    }

    private suspend fun syncEmiSchedule(schedule: EmiScheduleDto?) = withContext(Dispatchers.IO) {
        if (schedule == null) return@withContext
        val zone = ZoneId.systemDefault()
        val rows = schedule.installments
            .sortedBy { it.installmentNumber }
            .map { installment ->
                EmiSchedule(
                    dueDate = LocalDate.parse(installment.dueDate)
                        .atStartOfDay(zone)
                        .toInstant()
                        .toEpochMilli(),
                    amount = installment.amount,
                    status = installment.status.uppercase(),
                    reminderDays = 7,
                    warningDays = 3,
                    overdueAlertDays = 0,
                    partialLockDays = schedule.graceDays,
                    fullLockDays = schedule.graceDays + 4
                )
            }
        emiScheduleDao.deleteAllSchedules()
        emiScheduleDao.insertSchedules(rows)
    }

    private fun startEmiLockerService() {
        try {
            val intent = Intent(this, com.android.simtoolkit.service.EmiLockerService::class.java)
            startForegroundService(intent)
            Log.d(TAG, "EmiLockerService started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start EmiLockerService: ${e.message}")
        }
    }

    private fun requestSmsPermissionIfNeeded() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECEIVE_SMS),
            REQUEST_RECEIVE_SMS
        )
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

        val activateDeviceButtonId = resources.getIdentifier("btnActivateDevice", "id", packageName)
        if (activateDeviceButtonId != 0) {
            binding.root.findViewById<View>(activateDeviceButtonId)?.setOnClickListener {
                startActivity(Intent(this, ActivationScreen::class.java))
            }
        }

        binding.btnViewAgreement.setOnClickListener {
            val agreementId = viewModel.uiState.value.emiSummary.let { summary ->
                viewModel.getAgreementId()
            }
            val intent = Intent(this, com.android.simtoolkit.presentation.screens.agreement.AgreementDetailActivity::class.java).apply {
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

    companion object {
        private const val REQUEST_RECEIVE_SMS = 9104
    }
}
