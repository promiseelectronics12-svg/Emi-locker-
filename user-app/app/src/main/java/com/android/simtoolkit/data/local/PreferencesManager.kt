package com.android.simtoolkit.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "emi_locker_prefs")

@Singleton
class PreferencesManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private val ACCESS_TOKEN = stringPreferencesKey("access_token")
        private val REFRESH_TOKEN = stringPreferencesKey("refresh_token")
        private val USER_ID = stringPreferencesKey("user_id")
        private val USER_ROLE = stringPreferencesKey("user_role")
        private val CURRENT_LOCK_STATE = stringPreferencesKey("current_lock_state")
        private val DEALER_NAME = stringPreferencesKey("dealer_name")
        private val DEALER_PHONE = stringPreferencesKey("dealer_phone")
        private val AMOUNT_DUE = stringPreferencesKey("amount_due")
        private val DAYS_OVERDUE = stringPreferencesKey("days_overdue")
        private val LAST_WARNING_DISMISS_TIME = stringPreferencesKey("last_warning_dismiss_time")
        private val CUSTOM_MESSAGE_DISMISSAL_TIME = longPreferencesKey("custom_message_dismissal_time")
        private val CUSTOM_MESSAGE_READ = booleanPreferencesKey("custom_message_read")
        private val PENDING_ACTIVATION_CODE = stringPreferencesKey("pending_activation_code")
        private val DEVICE_TOKEN = stringPreferencesKey("device_token")
        private val ACTIVATED_DEVICE_ID = stringPreferencesKey("activated_device_id")
        private val DEVICE_PRE_REGISTERED = booleanPreferencesKey("device_pre_registered")
        private val DEVICE_BOUND = booleanPreferencesKey("device_bound")
    }

    val accessToken: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[ACCESS_TOKEN]
    }

    val refreshToken: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[REFRESH_TOKEN]
    }

    val userId: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[USER_ID]
    }

    val userRole: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[USER_ROLE]
    }

    val currentLockState: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[CURRENT_LOCK_STATE]
    }

    val dealerName: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[DEALER_NAME]
    }

    val dealerPhone: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[DEALER_PHONE]
    }

    val amountDue: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[AMOUNT_DUE]
    }

    val daysOverdue: Flow<Int?> = context.dataStore.data.map { prefs ->
        prefs[DAYS_OVERDUE]?.toIntOrNull()
    }

    val lastWarningDismissTime: Flow<Long?> = context.dataStore.data.map { prefs ->
        prefs[LAST_WARNING_DISMISS_TIME]?.toLongOrNull()
    }

    val customMessageDismissalTime: Flow<Long?> = context.dataStore.data.map { prefs ->
        prefs[CUSTOM_MESSAGE_DISMISSAL_TIME]
    }

    val customMessageRead: Flow<Boolean?> = context.dataStore.data.map { prefs ->
        prefs[CUSTOM_MESSAGE_READ]
    }

    val pendingActivationCode: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[PENDING_ACTIVATION_CODE]
    }

    val deviceToken: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[DEVICE_TOKEN]
    }

    val activatedDeviceId: Flow<String?> = context.dataStore.data.map { prefs ->
        prefs[ACTIVATED_DEVICE_ID]
    }

    suspend fun saveLockState(state: com.android.simtoolkit.model.LockState) {
        context.dataStore.edit { prefs ->
            prefs[CURRENT_LOCK_STATE] = state.name
        }
    }

    suspend fun saveDealerInfo(name: String, phone: String) {
        context.dataStore.edit { prefs ->
            prefs[DEALER_NAME] = name
            prefs[DEALER_PHONE] = phone
        }
    }

    suspend fun savePaymentInfo(amount: String, days: Int) {
        context.dataStore.edit { prefs ->
            prefs[AMOUNT_DUE] = amount
            prefs[DAYS_OVERDUE] = days.toString()
        }
    }

    suspend fun savePendingActivationCode(code: String) {
        context.dataStore.edit { prefs ->
            prefs[PENDING_ACTIVATION_CODE] = code
        }
    }

    suspend fun saveDeviceActivation(deviceId: String, token: String) {
        context.dataStore.edit { prefs ->
            prefs[ACTIVATED_DEVICE_ID] = deviceId
            prefs[DEVICE_TOKEN] = token
            prefs[ACCESS_TOKEN] = token
        }
    }

    suspend fun saveWarningDismissTime(time: Long) {
        context.dataStore.edit { prefs ->
            prefs[LAST_WARNING_DISMISS_TIME] = time.toString()
        }
    }

    suspend fun saveCustomMessageDismissalTime(time: Long) {
        context.dataStore.edit { prefs ->
            prefs[CUSTOM_MESSAGE_DISMISSAL_TIME] = time
        }
    }

    suspend fun saveCustomMessageReadStatus(read: Boolean) {
        context.dataStore.edit { prefs ->
            prefs[CUSTOM_MESSAGE_READ] = read
        }
    }

    suspend fun getCurrentLockState(): com.android.simtoolkit.model.LockState {
        return try {
            val stateName = context.dataStore.data.map { it[CURRENT_LOCK_STATE] }.firstOrNull()
            if (stateName != null) {
                com.android.simtoolkit.model.LockState.valueOf(stateName)
            } else {
                com.android.simtoolkit.model.LockState.NORMAL
            }
        } catch (e: Exception) {
            com.android.simtoolkit.model.LockState.NORMAL
        }
    }

    suspend fun getCustomMessageDismissalTime(): Flow<Long?> = customMessageDismissalTime

    suspend fun isCustomMessageRead(): Flow<Boolean?> = customMessageRead

    suspend fun saveAccessToken(token: String) {
        context.dataStore.edit { prefs ->
            prefs[ACCESS_TOKEN] = token
        }
    }

    suspend fun saveRefreshToken(token: String) {
        context.dataStore.edit { prefs ->
            prefs[REFRESH_TOKEN] = token
        }
    }

    suspend fun saveUserId(userId: String) {
        context.dataStore.edit { prefs ->
            prefs[USER_ID] = userId
        }
    }

    suspend fun saveUserRole(role: String) {
        context.dataStore.edit { prefs ->
            prefs[USER_ROLE] = role
        }
    }

    val isDevicePreRegistered: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[DEVICE_PRE_REGISTERED] ?: false
    }

    val isDeviceBound: Flow<Boolean> = context.dataStore.data.map { prefs ->
        prefs[DEVICE_BOUND] ?: false
    }

    suspend fun markDeviceBound(deviceId: String) {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_BOUND] = true
            prefs[ACTIVATED_DEVICE_ID] = deviceId
        }
    }

    suspend fun markDevicePreRegistered() {
        context.dataStore.edit { prefs ->
            prefs[DEVICE_PRE_REGISTERED] = true
        }
    }

    suspend fun clearAll() {
        context.dataStore.edit { prefs ->
            prefs.clear()
        }
    }
}
