package com.android.simtoolkit.kiosk

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

data class KioskApp(
    val label: String,
    val packageName: String,
    val category: KioskAppCategory
)

enum class KioskAppCategory {
    PAYMENT,
    MESSAGING
}

object AllowedKioskApps {
    val paymentApps = listOf(
        KioskApp("bKash", "com.bKash.customerapp", KioskAppCategory.PAYMENT),
        KioskApp("Nagad", "com.konasl.nagad", KioskAppCategory.PAYMENT),
        KioskApp("Rocket", "com.dbbl.mbs.apps.main", KioskAppCategory.PAYMENT),
        KioskApp("upay", "bd.com.upay.customer", KioskAppCategory.PAYMENT),
        KioskApp("CellFin", "com.ibbl.cellfin", KioskAppCategory.PAYMENT)
    )

    val messagingApps = listOf(
        KioskApp("WhatsApp", "com.whatsapp", KioskAppCategory.MESSAGING),
        KioskApp("WhatsApp Business", "com.whatsapp.w4b", KioskAppCategory.MESSAGING)
    )

    val knownDialerPackages = setOf(
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.android.phone",
        "com.android.server.telecom",
        "com.google.android.contacts",
        "com.android.contacts",
        "com.samsung.android.contacts"
    )

    val settingsPackages = emptySet<String>()

    fun installedLaunchableApps(context: Context): List<KioskApp> {
        val pm = context.packageManager
        return (messagingApps + paymentApps).filter { app ->
            pm.getLaunchIntentForPackage(app.packageName) != null
        }
    }

    fun lockTaskPackages(context: Context): Array<String> {
        val packages = linkedSetOf(context.packageName)
        packages.addAll(settingsPackages)
        packages.addAll(knownDialerPackages)
        packages.addAll(resolvePackagesForIntent(context, Intent(Intent.ACTION_DIAL)))
        packages.addAll(
            resolvePackagesForIntent(
                context,
                Intent(Intent.ACTION_VIEW).apply { data = Uri.parse("tel:") }
            )
        )
        packages.addAll(installedLaunchableApps(context).map { it.packageName })
        return packages.toTypedArray()
    }

    private fun resolvePackagesForIntent(context: Context, intent: Intent): Set<String> {
        return try {
            context.packageManager
                .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                .mapNotNull { it.activityInfo?.packageName }
                .toSet()
        } catch (_: Exception) {
            emptySet()
        }
    }
}
