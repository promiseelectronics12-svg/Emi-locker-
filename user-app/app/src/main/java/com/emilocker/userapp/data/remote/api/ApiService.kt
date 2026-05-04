package com.emilocker.userapp.data.remote.api

import com.emilocker.userapp.data.remote.dto.*
import retrofit2.Response
import retrofit2.http.*

interface ApiService {

    @POST("api/v1/auth/login")
    suspend fun login(@Body request: LoginRequest): Response<AuthResponse>

    @POST("api/v1/auth/register")
    suspend fun register(@Body request: RegisterRequest): Response<AuthResponse>

    @POST("api/v1/auth/refresh")
    suspend fun refreshToken(@Body body: Map<String, String>): Response<AuthResponse>

    @POST("api/v1/auth/logout")
    suspend fun logout(@Body body: Map<String, String>): Response<Unit>

    @GET("api/v1/users/me")
    suspend fun getCurrentUser(): Response<UserDto>

    @GET("api/v1/devices")
    suspend fun getDevices(): Response<DeviceListResponse>

    @GET("api/v1/devices/{deviceId}")
    suspend fun getDevice(@Path("deviceId") deviceId: String): Response<DeviceResponse>

    @GET("api/v1/agreements")
    suspend fun getAgreements(): Response<AgreementListResponse>

    @GET("api/v1/agreements/{agreementId}")
    suspend fun getAgreement(@Path("agreementId") agreementId: String): Response<AgreementDetailResponse>

    @GET("api/v1/payments")
    suspend fun getPaymentHistory(): Response<PaymentListResponse>

    @POST("api/v1/devices/fcm-token")
    @FormUrlEncoded
    suspend fun updateFcmToken(@Field("token") token: String): Response<Unit>
}

data class DeviceListResponse(
    val devices: List<DeviceDto>,
    val pagination: PaginationDto
)

data class DeviceDto(
    val id: String,
    val imei: String,
    val model: String?,
    val manufacturer: String?,
    val status: String,
    val enrollmentDate: String?
)

data class DeviceResponse(
    val device: DeviceDto,
    val agreements: List<AgreementDto>
)

data class AgreementListResponse(
    val agreements: List<AgreementDto>,
    val pagination: PaginationDto
)

data class AgreementDto(
    val id: String,
    val emiNumber: String,
    val totalAmount: Double,
    val monthlyPayment: Double,
    val downPayment: Double,
    val tenureMonths: Int,
    val startDate: String,
    val endDate: String,
    val status: String,
    val riskLevel: String
)

data class AgreementDetailResponse(
    val agreement: AgreementDto,
    val payments: List<PaymentDto>,
    val device: DeviceDto?
)

data class PaymentListResponse(
    val payments: List<PaymentDto>,
    val pagination: PaginationDto
)

data class PaymentDto(
    val id: String,
    val amount: Double,
    val paymentDate: String,
    val paymentMethod: String,
    val status: String
)

data class PaginationDto(
    val page: Int,
    val limit: Int,
    val total: Int,
    val pages: Int
)