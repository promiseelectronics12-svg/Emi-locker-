package com.android.simtoolkit.ui.payment

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.android.simtoolkit.R
import com.android.simtoolkit.databinding.ItemPaymentHistoryBinding
import com.android.simtoolkit.presentation.screens.dashboard.PaymentHistoryItem
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class PaymentHistoryAdapter : ListAdapter<PaymentHistoryItem, PaymentHistoryAdapter.ViewHolder>(DiffCallback) {

    private val dateFormat = SimpleDateFormat("dd MMM yyyy", Locale.US)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemPaymentHistoryBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ViewHolder(private val binding: ItemPaymentHistoryBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(item: PaymentHistoryItem) {
            binding.tvPaymentAmount.text =
                "৳${String.format(Locale.US, "%,.0f", item.amount)}"
            binding.tvPaymentDate.text = dateFormat.format(Date(item.paymentDate))
            binding.tvPaymentMethod.text =
                item.paymentMethod.replaceFirstChar { it.uppercaseChar() }
            binding.tvPaymentStatus.text =
                item.status.replaceFirstChar { it.uppercaseChar() }
            binding.tvTransactionId.text = item.id.take(12)

            val statusColorRes = when (item.status.lowercase(Locale.US)) {
                "confirmed", "paid", "success" -> R.color.payment_success
                "pending" -> R.color.payment_pending
                "failed", "rejected" -> R.color.payment_failed
                else -> R.color.payment_default
            }
            val statusColor = ContextCompat.getColor(binding.root.context, statusColorRes)
            binding.tvPaymentStatus.setTextColor(statusColor)
            binding.statusIndicator.setBackgroundColor(statusColor)
        }
    }

    companion object DiffCallback : DiffUtil.ItemCallback<PaymentHistoryItem>() {
        override fun areItemsTheSame(old: PaymentHistoryItem, new: PaymentHistoryItem) =
            old.id == new.id

        override fun areContentsTheSame(old: PaymentHistoryItem, new: PaymentHistoryItem) =
            old == new
    }
}

