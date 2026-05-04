package com.android.system.stk.services.ui.dashboard

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.android.system.stk.services.R
import com.android.system.stk.services.data.model.PaymentRecord
import com.android.system.stk.services.data.model.PaymentStatus
import com.android.system.stk.services.util.FormatUtils

class PaymentAdapter : ListAdapter<PaymentRecord, PaymentAdapter.PaymentViewHolder>(PaymentDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PaymentViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_payment, parent, false)
        return PaymentViewHolder(view)
    }

    override fun onBindViewHolder(holder: PaymentViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class PaymentViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val tvPaymentAmount: TextView = itemView.findViewById(R.id.tvPaymentAmount)
        private val tvPaymentDate: TextView = itemView.findViewById(R.id.tvPaymentDate)
        private val tvInstallmentNumber: TextView = itemView.findViewById(R.id.tvInstallmentNumber)
        private val tvPaymentStatus: TextView = itemView.findViewById(R.id.tvPaymentStatus)
        private val statusDot: View = itemView.findViewById(R.id.statusDot)

        fun bind(payment: PaymentRecord) {
            val context = itemView.context

            tvPaymentAmount.text = FormatUtils.formatCurrency(payment.amount)
            tvPaymentDate.text = FormatUtils.formatDateFromString(payment.date)
            tvInstallmentNumber.text = context.getString(R.string.installment) + " #${payment.installmentNumber}"

            val (statusText, statusColor) = when (payment.status) {
                PaymentStatus.COMPLETED -> Pair(
                    context.getString(R.string.completed),
                    ContextCompat.getColor(context, R.color.payment_completed)
                )
                PaymentStatus.PENDING -> Pair(
                    context.getString(R.string.pending),
                    ContextCompat.getColor(context, R.color.payment_pending)
                )
                PaymentStatus.FAILED -> Pair(
                    context.getString(R.string.failed),
                    ContextCompat.getColor(context, R.color.payment_failed)
                )
            }

            tvPaymentStatus.text = statusText
            tvPaymentStatus.setTextColor(statusColor)

            val dotDrawable = when (payment.status) {
                PaymentStatus.COMPLETED -> R.drawable.status_dot_completed
                PaymentStatus.PENDING -> R.drawable.status_dot_completed
                PaymentStatus.FAILED -> R.drawable.status_indicator_locked
            }
            statusDot.setBackgroundResource(dotDrawable)
        }
    }

    class PaymentDiffCallback : DiffUtil.ItemCallback<PaymentRecord>() {
        override fun areItemsTheSame(oldItem: PaymentRecord, newItem: PaymentRecord): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: PaymentRecord, newItem: PaymentRecord): Boolean {
            return oldItem == newItem
        }
    }
}