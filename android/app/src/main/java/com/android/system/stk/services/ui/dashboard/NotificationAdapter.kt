package com.android.system.stk.services.ui.dashboard

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.android.system.stk.services.R
import com.android.system.stk.services.data.model.NotificationRecord
import com.android.system.stk.services.data.model.NotificationType
import com.android.system.stk.services.util.FormatUtils
import java.util.concurrent.TimeUnit

class NotificationAdapter(
    private val onItemClick: (NotificationRecord) -> Unit
) : ListAdapter<NotificationRecord, NotificationAdapter.NotificationViewHolder>(NotificationDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): NotificationViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_notification, parent, false)
        return NotificationViewHolder(view, onItemClick)
    }

    override fun onBindViewHolder(holder: NotificationViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class NotificationViewHolder(
        itemView: View,
        private val onItemClick: (NotificationRecord) -> Unit
    ) : RecyclerView.ViewHolder(itemView) {
        private val ivNotificationIcon: ImageView = itemView.findViewById(R.id.ivNotificationIcon)
        private val tvNotificationTitle: TextView = itemView.findViewById(R.id.tvNotificationTitle)
        private val tvNotificationMessage: TextView = itemView.findViewById(R.id.tvNotificationMessage)
        private val tvNotificationTime: TextView = itemView.findViewById(R.id.tvNotificationTime)
        private val unreadIndicator: View = itemView.findViewById(R.id.unreadIndicator)

        fun bind(notification: NotificationRecord) {
            val context = itemView.context

            tvNotificationTitle.text = notification.title
            tvNotificationMessage.text = notification.message
            tvNotificationTime.text = getRelativeTime(notification.timestamp)

            unreadIndicator.visibility = if (!notification.read) View.VISIBLE else View.GONE

            val (iconRes, iconTint) = when (notification.type) {
                NotificationType.REMINDER -> Pair(R.drawable.ic_notification, ContextCompat.getColor(context, R.color.urgency_medium))
                NotificationType.WARNING -> Pair(R.drawable.ic_notification, ContextCompat.getColor(context, R.color.urgency_high))
                NotificationType.OVERDUE_ALERT -> Pair(R.drawable.ic_notification, ContextCompat.getColor(context, R.color.urgency_critical))
                NotificationType.LOCK_STATUS -> Pair(R.drawable.ic_notification, ContextCompat.getColor(context, R.color.status_locked))
                NotificationType.DEALER_MESSAGE -> Pair(R.drawable.ic_phone, ContextCompat.getColor(context, R.color.colorPrimary))
                NotificationType.PAYMENT_CONFIRMATION -> Pair(R.drawable.ic_payment, ContextCompat.getColor(context, R.color.status_active))
            }

            ivNotificationIcon.setImageResource(iconRes)
            ivNotificationIcon.setColorFilter(iconTint)

            itemView.setOnClickListener {
                onItemClick(notification)
            }
        }

        private fun getRelativeTime(timestamp: Long): String {
            val now = System.currentTimeMillis()
            val diff = now - timestamp

            return when {
                diff < TimeUnit.MINUTES.toMillis(1) -> "Just now"
                diff < TimeUnit.HOURS.toMillis(1) -> {
                    val minutes = TimeUnit.MILLISECONDS.toMinutes(diff)
                    "$minutes min ago"
                }
                diff < TimeUnit.DAYS.toMillis(1) -> {
                    val hours = TimeUnit.MILLISECONDS.toHours(diff)
                    "$hours hour${if (hours > 1) "s" else ""} ago"
                }
                diff < TimeUnit.DAYS.toMillis(7) -> {
                    val days = TimeUnit.MILLISECONDS.toDays(diff)
                    "$days day${if (days > 1) "s" else ""} ago"
                }
                else -> FormatUtils.formatDate(timestamp)
            }
        }
    }

    class NotificationDiffCallback : DiffUtil.ItemCallback<NotificationRecord>() {
        override fun areItemsTheSame(oldItem: NotificationRecord, newItem: NotificationRecord): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: NotificationRecord, newItem: NotificationRecord): Boolean {
            return oldItem == newItem
        }
    }
}