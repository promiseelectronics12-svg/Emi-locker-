package com.emilocker.userapp.data.repository

import com.emilocker.userapp.BuildConfig
import com.emilocker.userapp.data.local.PreferencesManager
import com.emilocker.userapp.data.remote.api.ApiService
import com.emilocker.userapp.data.remote.dto.AuthResponse
import com.emilocker.userapp.data.remote.dto.LoginRequest
import com.emilocker.userapp.data.remote.dto.RegisterRequest
import com.emilocker.userapp.data.remote.dto.ApiError
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val apiService: ApiService,
    private val preferencesManager: PreferencesManager
) {
    private val apiBaseUrl: String = BuildConfig.API_BASE_URL

    suspend fun login(nid: String, password: String): Result<AuthResponse> {
        return try {
            val response = apiService.login(LoginRequest(nid = nid, password = password))
            if (response.isSuccessful && response.body() != null) {
                val authResponse = response.body()!!
                preferencesManager.saveAccessToken(authResponse.accessToken)
                preferencesManager.saveRefreshToken(authResponse.refreshToken)
                preferencesManager.saveUserId(authResponse.user.id)
                preferencesManager.saveUserRole(authResponse.user.role)
                Result.success(authResponse)
            } else {
                val errorBody = response.errorBody()?.string()
                val error = parseApiError(errorBody)
                Result.failure(Exception(error.message))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun register(
        nid: String,
        name: String,
        phone: String,
        email: String?,
        password: String
    ): Result<AuthResponse> {
        return try {
            val response = apiService.register(
                RegisterRequest(
                    nid = nid,
                    name = name,
                    phone = phone,
                    email = email,
                    password = password
                )
            )
            if (response.isSuccessful && response.body() != null) {
                val authResponse = response.body()!!
                preferencesManager.saveAccessToken(authResponse.accessToken)
                preferencesManager.saveRefreshToken(authResponse.refreshToken)
                preferencesManager.saveUserId(authResponse.user.id)
                preferencesManager.saveUserRole(authResponse.user.role)
                Result.success(authResponse)
            } else {
                val errorBody = response.errorBody()?.string()
                val error = parseApiError(errorBody)
                Result.failure(Exception(error.message))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun refreshToken(): Result<AuthResponse> {
        return try {
            val refreshToken = preferencesManager.refreshToken.first() ?: return Result.failure(Exception("No refresh token"))
            val response = apiService.refreshToken(mapOf("refreshToken" to refreshToken))
            if (response.isSuccessful && response.body() != null) {
                val authResponse = response.body()!!
                preferencesManager.saveAccessToken(authResponse.accessToken)
                preferencesManager.saveRefreshToken(authResponse.refreshToken)
                Result.success(authResponse)
            } else {
                Result.failure(Exception("Token refresh failed"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun logout() {
        try {
            val refreshToken = preferencesManager.refreshToken.first()
            refreshToken?.let { apiService.logout(mapOf("refreshToken" to it)) }
        } catch (_: Exception) { }
        preferencesManager.clearAll()
    }

    suspend fun isLoggedIn(): Boolean {
        return preferencesManager.accessToken.first() != null
    }

    fun getAccessToken(): Flow<String?> = preferencesManager.accessToken
    fun getUserId(): Flow<String?> = preferencesManager.userId

    private fun parseApiError(errorBody: String?): ApiError {
        return try {
            errorBody?.let { com.google.gson.Gson().fromJson(it, ApiError::class.java) } ?: ApiError("Unknown error")
        } catch (_: Exception) {
            ApiError("Unknown error")
        }
    }
}