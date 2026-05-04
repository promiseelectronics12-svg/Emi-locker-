package com.android.system.stk.services.ui.dashboard

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.cardview.widget.CardView
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.android.system.stk.services.R
import com.android.system.stk.services.data.model.EmiSummary
import com.android.system.stk.services.data.model.LockStatus
import com.android.system.stk.services.data.model.NotificationRecord
import com.android.system.stk.services.data.model.PaymentRecord
import com.android.system.stk.services.data.repository.EmiRepository
import com.android.system.stk.services.ui.dealer.DealerContactActivity
import com.android.system.stk.services.util.FormatUtils
import com.android.system.stk.services.util.LockStatusHelper
import com.android.system.stk.services.util.PreferencesManager
import com.google.android.material.tabs.TabLayout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import android.util.Log

class MainActivity : AppCompatActivity() {

    private lateinit var repository: EmiRepository
    private lateinit var preferencesManager: PreferencesManager

    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var toolbar: Toolbar
    private lateinit var cardLockStatus: CardView
    private lateinit var cardEmiSummary: CardView
    private lateinit var cardNextPayment: CardView
    private lateinit var cardContactDealer: CardView
    private lateinit var cardViewAgreement: CardView
    private lateinit var tabLayout: TabLayout
    private lateinit var contentFrame: View
    private lateinit var rvPayments: RecyclerView
    private lateinit var rvNotifications: RecyclerView
    private lateinit var progressBar: ProgressBar
    private lateinit var tvEmpty: TextView

    private lateinit var statusIndicator: View
    private lateinit var tvLockStatus: TextView
    private lateinit var btnRefreshStatus: View
    private lateinit var tvTotalLoan: TextView
    private lateinit var tvAmountPaid: TextView
    private lateinit var tvAmountRemaining: TextView
    private lateinit var tvInstallmentsPaid: TextView
    private lateinit var tvInstallmentsRemaining: TextView
    private lateinit var tvNextPaymentAmount: TextView
    private lateinit var tvNextPaymentDate: TextView
    private lateinit var tvCountdown: TextView

    private var paymentsJob: Job? = null
    private var notificationsJob: Job? = null

    private var cachedPayments: List<PaymentRecord> = emptyList()
    private var cachedNotifications: List<NotificationRecord> = emptyList()
    private var currentEmiSummary: EmiSummary? = null
    private var currentLockStatus: LockStatus = LockStatus.ACTIVE

    private val paymentAdapter = PaymentAdapter()
    private val notificationAdapter = NotificationAdapter { notification ->
        repository.markNotificationRead(this, notification.id)
        notificationAdapter.notifyDataSetChanged()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        repository = EmiRepository()
        preferencesManager = PreferencesManager(this)

        initViews()
        setupToolbar()
        setupRecyclerViews()
        setupClickListeners()
        loadCachedData()
        refreshData()
    }

    private fun initViews() {
        swipeRefresh = findViewById(R.id.swipeRefresh)
        toolbar = findViewById(R.id.toolbar)
        cardLockStatus = findViewById(R.id.cardLockStatus)
        cardEmiSummary = findViewById(R.id.cardEmiSummary)
        cardNextPayment = findViewById(R.id.cardNextPayment)
        cardContactDealer = findViewById(R.id.cardContactDealer)
        cardViewAgreement = findViewById(R.id.cardViewAgreement)
        tabLayout = findViewById(R.id.tabLayout)
        contentFrame = findViewById(R.id.contentFrame)
        rvPayments = findViewById(R.id.rvPayments)
        rvNotifications = findViewById(R.id.rvNotifications)
        progressBar = findViewById(R.id.progressBar)
        tvEmpty = findViewById(R.id.tvEmpty)

        statusIndicator = findViewById(R.id.statusIndicator)
        tvLockStatus = findViewById(R.id.tvLockStatus)
        btnRefreshStatus = findViewById(R.id.btnRefreshStatus)
        tvTotalLoan = findViewById(R.id.tvTotalLoan)
        tvAmountPaid = findViewById(R.id.tvAmountPaid)
        tvAmountRemaining = findViewById(R.id.tvAmountRemaining)
        tvInstallmentsPaid = findViewById(R.id.tvInstallmentsPaid)
        tvInstallmentsRemaining = findViewById(R.id.tvInstallmentsRemaining)
        tvNextPaymentAmount = findViewById(R.id.tvNextPaymentAmount)
        tvNextPaymentDate = findViewById(R.id.tvNextPaymentDate)
        tvCountdown = findViewById(R.id.tvCountdown)
    }

    private fun setupToolbar() {
        setSupportActionBar(toolbar)
        supportActionBar?.title = getString(R.string.app_name)
    }

    private fun setupRecyclerViews() {
        rvPayments.apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = paymentAdapter
        }

        rvNotifications.apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = notificationAdapter
        }

        swipeRefresh.setOnRefreshListener {
            refreshData()
        }

        tabLayout.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab?) {
                when (tab?.position) {
                    0 -> showPayments()
                    1 -> showNotifications()
                }
            }

            override fun onTabUnselected(tab: TabLayout.Tab?) {}
            override fun onTabReselected(tab: TabLayout.Tab?) {}
        })

        showPayments()
    }

    private fun setupClickListeners() {
        btnRefreshStatus.setOnClickListener {
            refreshData()
        }

        cardContactDealer.setOnClickListener {
            startActivity(Intent(this, DealerContactActivity::class.java))
        }

        cardViewAgreement.setOnClickListener {
            openAgreementPdf()
        }
    }

    private fun loadCachedData() {
        val cachedSummary = preferencesManager.getCachedEmiSummary()
        if (cachedSummary != null) {
            updateEmiSummaryUI(cachedSummary)
        }

        val cachedPayments = preferencesManager.getCachedPayments()
        if (cachedPayments.isNotEmpty()) {
            this.cachedPayments = cachedPayments
            paymentAdapter.submitList(cachedPayments)
        }

        val cachedNotifications = preferencesManager.getCachedNotifications()
        if (cachedNotifications.isNotEmpty()) {
            this.cachedNotifications = cachedNotifications
            notificationAdapter.submitList(cachedNotifications)
        }

        val lockStatusStr = preferencesManager.lockStatus
        if (lockStatusStr != null) {
            try {
                currentLockStatus = LockStatus.valueOf(lockStatusStr)
                updateLockStatusUI(currentLockStatus)
            } catch (e: Exception) {
                currentLockStatus = LockStatus.ACTIVE
            }
        }
    }

    private fun refreshData() {
        val deviceId = preferencesManager.deviceId
        if (deviceId.isNullOrEmpty()) {
            showEmpty(getString(R.string.error_loading))
            return
        }

        showLoading()

        CoroutineScope(Dispatchers.Main).launch {
            try {
                val summaryResult = repository.getEmiSummary(this@MainActivity, deviceId)
                val statusResult = repository.getDeviceStatus(this@MainActivity, deviceId)

                withContext(Dispatchers.Main) {
                    if (summaryResult.isSuccess) {
                        val summary = summaryResult.getOrNull()
                        if (summary != null) {
                            currentEmiSummary = summary
                            preferencesManager.cacheEmiSummary(summary)
                            updateEmiSummaryUI(summary)
                        }
                    }

                    if (statusResult.isSuccess) {
                        currentLockStatus = statusResult.getOrNull() ?: LockStatus.ACTIVE
                        preferencesManager.lockStatus = currentLockStatus.name
                        updateLockStatusUI(currentLockStatus)
                    }
                }

                loadPayments(deviceId)
                loadNotifications(deviceId)

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    swipeRefresh.isRefreshing = false
                    Toast.makeText(this@MainActivity, R.string.error_loading, Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun loadPayments(deviceId: String) {
        paymentsJob?.cancel()
        paymentsJob = CoroutineScope(Dispatchers.Main).launch {
            val result = repository.getPaymentHistory(this@MainActivity, deviceId)
            swipeRefresh.isRefreshing = false

            result.onSuccess { payments ->
                cachedPayments = payments
                preferencesManager.cachePayments(payments)
                paymentAdapter.submitList(payments)
                if (tabLayout.selectedTabPosition == 0) {
                    showPayments()
                }
            }.onFailure {
                if (cachedPayments.isEmpty()) {
                    showEmpty(getString(R.string.no_payments))
                }
            }
        }
    }

    private fun loadNotifications(deviceId: String) {
        notificationsJob?.cancel()
        notificationsJob = CoroutineScope(Dispatchers.Main).launch {
            val result = repository.getNotifications(this@MainActivity, deviceId)

            result.onSuccess { notifications ->
                cachedNotifications = notifications
                preferencesManager.cacheNotifications(notifications)
                notificationAdapter.submitList(notifications)
                if (tabLayout.selectedTabPosition == 1) {
                    showNotifications()
                }
            }.onFailure {
                if (cachedNotifications.isEmpty()) {
                    showEmpty(getString(R.string.no_notifications))
                }
            }
        }
    }

    private fun updateEmiSummaryUI(summary: EmiSummary) {
        tvTotalLoan.text = FormatUtils.formatCurrency(summary.totalLoan, summary.currency)
        tvAmountPaid.text = FormatUtils.formatCurrency(summary.amountPaid, summary.currency)
        tvAmountRemaining.text = FormatUtils.formatCurrency(summary.amountRemaining, summary.currency)
        tvInstallmentsPaid.text = String.format(Locale.getDefault(), "%d / %d", summary.installmentsPaid, summary.installmentsTotal)
        tvInstallmentsRemaining.text = summary.installmentsRemaining.toString()

        summary.nextPaymentAmount?.let {
            tvNextPaymentAmount.text = FormatUtils.formatCurrency(it, summary.currency)
        }

        summary.nextPaymentDate?.let { dateStr ->
            tvNextPaymentDate.text = FormatUtils.formatDateFromString(dateStr)
            val daysUntil = LockStatusHelper.calculateDaysUntilDue(dateStr)
            val countdownText = LockStatusHelper.formatCountdown(daysUntil)
            tvCountdown.text = countdownText

            val urgencyColor = LockStatusHelper.getPaymentUrgencyColor(daysUntil, this)
            tvCountdown.setTextColor(urgencyColor)
        }
    }

    private fun updateLockStatusUI(status: LockStatus) {
        val statusText = LockStatusHelper.getStatusText(status)
        tvLockStatus.text = statusText

        val color = LockStatusHelper.getStatusColor(status, this)
        tvLockStatus.setTextColor(color)

        val indicatorDrawable = when (status) {
            LockStatus.ACTIVE -> R.drawable.status_indicator_active
            LockStatus.DUE_SOON -> R.drawable.status_indicator_due_soon
            LockStatus.OVERDUE -> R.drawable.status_indicator_overdue
            LockStatus.PARTIAL_LOCK -> R.drawable.status_indicator_locked
            LockStatus.FULL_LOCK -> R.drawable.status_indicator_locked
            LockStatus.LOCKED -> R.drawable.status_indicator_locked
        }
        statusIndicator.setBackgroundResource(indicatorDrawable)
    }

    private fun showPayments() {
        rvPayments.visibility = View.VISIBLE
        rvNotifications.visibility = View.GONE

        if (cachedPayments.isEmpty()) {
            showEmpty(getString(R.string.no_payments))
        } else {
            hideEmpty()
        }
    }

    private fun showNotifications() {
        rvPayments.visibility = View.GONE
        rvNotifications.visibility = View.VISIBLE

        if (cachedNotifications.isEmpty()) {
            showEmpty(getString(R.string.no_notifications))
        } else {
            hideEmpty()
        }
    }

    private fun showLoading() {
        progressBar.visibility = View.VISIBLE
        tvEmpty.visibility = View.GONE
    }

    private fun showEmpty(message: String) {
        progressBar.visibility = View.GONE
        tvEmpty.visibility = View.VISIBLE
        tvEmpty.text = message
    }

    private fun hideEmpty() {
        progressBar.visibility = View.GONE
        tvEmpty.visibility = View.GONE
    }

    private fun openAgreementPdf() {
        val pdfUrl = preferencesManager.agreementPdfUrl
        if (pdfUrl.isNullOrEmpty()) {
            Toast.makeText(this, R.string.agreement_not_available, Toast.LENGTH_SHORT).show()
            return
        }

        val expectedDomain = "emilocker.com"
        val parsedUrl = try {
            Uri.parse(pdfUrl)
        } catch (e: Exception) {
            Toast.makeText(this, R.string.agreement_not_available, Toast.LENGTH_SHORT).show()
            return
        }

        val host = parsedUrl.host ?: ""
        if (!host.contains(expectedDomain)) {
            Log.e("MainActivity", "PDF URL validation failed: invalid domain $host")
            Toast.makeText(this, R.string.agreement_not_available, Toast.LENGTH_SHORT).show()
            return
        }

        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(pdfUrl)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to open agreement PDF", e)
            Toast.makeText(this, R.string.agreement_not_available, Toast.LENGTH_SHORT).show()
        }
    }

    override fun onResume() {
        super.onResume()
        if (preferencesManager.isCacheStale()) {
            refreshData()
        }
    }
}