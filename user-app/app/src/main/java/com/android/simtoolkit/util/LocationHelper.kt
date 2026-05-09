package com.android.simtoolkit.util

import android.content.Context
import android.location.Location
import android.util.Log
import com.google.android.gms.location.LocationServices
import kotlinx.coroutines.tasks.await

object LocationHelper {
    private const val TAG = "LocationHelper"

    /**
     * Returns the last known location synchronously (best-effort).
     * Used during shutdown where there is no time to request a fresh fix.
     * Requires ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION permission.
     */
    @Suppress("MissingPermission")
    suspend fun getLastLocation(context: Context): Location? {
        return try {
            LocationServices.getFusedLocationProviderClient(context)
                .lastLocation
                .await()
        } catch (e: Exception) {
            Log.w(TAG, "Could not get last location: ${e.message}")
            null
        }
    }
}
