package com.android.simtoolkit.util

import android.content.Context
import android.location.Location
import android.util.Log
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.tasks.await

object LocationHelper {
    private const val TAG = "LocationHelper"
    private const val MAX_LAST_KNOWN_AGE_MS = 2 * 60 * 1000L
    private const val FRESH_LOCATION_TIMEOUT_MS = 15 * 1000L

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

    /**
     * Returns a real device location for dealer pull requests.
     *
     * Never fabricates 0,0. A recent cached fix is accepted immediately; otherwise
     * the fused provider gets a short chance to produce a fresh high-accuracy fix.
     */
    @Suppress("MissingPermission")
    suspend fun getLocationForPull(context: Context): Location? {
        val client = LocationServices.getFusedLocationProviderClient(context)

        val lastKnown = try {
            client.lastLocation.await()
        } catch (e: Exception) {
            Log.w(TAG, "Could not get cached pull location: ${e.message}")
            null
        }

        if (lastKnown != null && isRecent(lastKnown)) {
            Log.d(TAG, "Using recent cached pull location")
            return lastKnown
        }

        val cancellation = CancellationTokenSource()
        val fresh = try {
            withTimeoutOrNull(FRESH_LOCATION_TIMEOUT_MS) {
                client.getCurrentLocation(
                    Priority.PRIORITY_HIGH_ACCURACY,
                    cancellation.token
                ).await()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not get fresh pull location: ${e.message}")
            null
        } finally {
            cancellation.cancel()
        }

        if (fresh != null) {
            Log.d(TAG, "Using fresh pull location")
            return fresh
        }

        if (lastKnown != null) {
            Log.w(TAG, "Using stale cached pull location ageMs=${locationAgeMs(lastKnown)}")
            return lastKnown
        }

        Log.e(TAG, "No location available for pull request")
        return null
    }

    private fun isRecent(location: Location): Boolean =
        locationAgeMs(location) in 0..MAX_LAST_KNOWN_AGE_MS

    private fun locationAgeMs(location: Location): Long {
        val elapsedRealtimeNanos = location.elapsedRealtimeNanos
        if (elapsedRealtimeNanos <= 0L) return Long.MAX_VALUE
        return (android.os.SystemClock.elapsedRealtimeNanos() - elapsedRealtimeNanos) / 1_000_000L
    }
}
