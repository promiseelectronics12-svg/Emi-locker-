package com.android.simtoolkit.ui.notification

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.android.simtoolkit.R
import com.android.simtoolkit.databinding.ItemNotificationHistoryBinding
import com.android.simtoolkit.presentation.screens.dashboard.NotificationHistoryItem
import com.android.simtoolkit.presentation.screens.dashboard.NotificationType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NotificationHistoryAdapter(
    private val onItemClick: (NotificationHistoryItem) -> Unit
) : ListAdapter<NotificationHistoryItem, NotificationHistoryAdapter.ViewHolder>(DiffCallback) {

    private val dateFormat = SimpleDateFormat("dd MMM yyyy, HH:mm", Locale.US)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemNotificationHistoryBinding.inflate(
            LayoutInflater.from(parent.context), parent, false
        )
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ViewHolder(private val binding: ItemNotificationHistoryBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(item: NotificationHistoryItem) {
            binding.tvNotificationTitle.text = item.title
            binding.tvNotificationMessage.text = item.message
            binding.tvNotificationTime.text = dateFormat.format(Date(item.timestamp))

            val priorityColorRes = when (item.type) {
                NotificationType.REMINDER -> R.color.notification_reminder
                NotificationType.WARNING -> R.color.notification_warning
                NotificationType.OVERDUE_ALERT -> R.color.notification_overdue
                NotificationType.DEALER_MESSAGE -> R.color.notification_dealer
                NotificationType.SYSTEM_MESSAGE -> R.color.notification_system
            }
            val priorityColor = ContextCompat.getColor(binding.root.context, priorityColorRes)
            binding.priorityIndicator.setBackgroundColor(priorityColor)
            binding.ivNotificationIcon.backgroundTintList =
                android.content.res.ColorStateList.valueOf(priorityColor)

            if (item.isRead) {
                binding.root.alpha = 0.7f
                binding.cardNotification.setCardBackgroundColor(
                    ContextCompat.getColor(binding.root.context, R.color.notification_read_background)
                )
                binding.tvNotificationTitle.setTypeface(binding.tvNotificationTitle.typeface, android.graphics.Typeface.NORMAL)
            } else {
                binding.root.alpha = 1.0f
                binding.cardNotification.setCardBackgroundColor(
                    ContextCompat.getColor(binding.root.context, R.color.card_background)
                )
                binding.tvNotificationTitle.setTypeface(binding.tvNotificationTitle.typeface, android.graphics.Typeface.BOLD)
            }
            binding.cardNotification.setOnClickListener { onItemClick(item) }
        }
    }

    companion object DiffCallback : DiffUtil.ItemCallback<NotificationHistoryItem>() {
        override fun areItemsTheSame(old: NotificationHistoryItem, new: NotificationHistoryItem) =
            old.id == new.id

        override fun areContentsTheSame(old: NotificationHistoryItem, new: NotificationHistoryItem) =
            old == new
    }
}

