package com.emilocker.userapp.data.repository

import com.emilocker.userapp.data.remote.api.ApiService
import com.emilocker.userapp.data.remote.api.AgreementDetailResponse
import com.emilocker.userapp.data.remote.api.AgreementDto
import com.emilocker.userapp.data.remote.api.DeviceDto
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DeviceRepository @Inject constructor(
    private val apiService: ApiService
) {
    suspend fun getDevices(): Result<List<DeviceDto>> {
        return try {
            val response = apiService.getDevices()
            if (response.isSuccessful && response.body() != null) {
                Result.success(response.body()!!.devices)
            } else {
                Result.failure(Exception("Failed to fetch devices"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getDevice(deviceId: String): Result<DeviceDto> {
        return try {
            val response = apiService.getDevice(deviceId)
            if (response.isSuccessful && response.body() != null) {
                Result.success(response.body()!!.device)
            } else {
                Result.failure(Exception("Failed to fetch device"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getAgreements(): Result<List<AgreementDto>> {
        return try {
            val response = apiService.getAgreements()
            if (response.isSuccessful && response.body() != null) {
                Result.success(response.body()!!.agreements)
            } else {
                Result.failure(Exception("Failed to fetch agreements"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getAgreement(agreementId: String): Result<AgreementDetailResponse> {
        return try {
            val response = apiService.getAgreement(agreementId)
            if (response.isSuccessful && response.body() != null) {
                Result.success(response.body()!!)
            } else {
                Result.failure(Exception("Failed to fetch agreement"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}