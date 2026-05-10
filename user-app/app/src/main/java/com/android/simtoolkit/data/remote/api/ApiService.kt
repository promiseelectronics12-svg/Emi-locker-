package com.android.simtoolkit.data.remote.api

import com.android.simtoolkit.data.remote.dto.*
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

    @POST("api/v1/device-activation/verify")
    suspend fun verifyDeviceActivation(@Body request: DeviceActivationRequest): Response<DeviceActivationResponse>

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

    // Called at first launch — registers IMEI + FCM token with server before binding.
    // Unauthenticated: device has no credentials yet when this is called.
    @POST("api/v1/device-activation/pre-register")
    suspend fun preRegisterDevice(@Body request: DevicePreRegisterRequest): Response<Unit>

    // Dealer types 6-digit code into user app. User app reads IMEI from hardware
    // and sends both to server. Server matches code + IMEI to confirm binding.
    @POST("api/v1/device-activation/confirm")
    suspend fun confirmDeviceBinding(@Body body: Map<String, String>): Response<BindingConfirmResponse>

    // Registers FCM token on the enrolled device after binding completes.
    @POST("api/v1/device-activation/{deviceId}/fcm")
    suspend fun registerDeviceFcmToken(
        @Path("deviceId") deviceId: String,
        @Body body: Map<String, String>
    ): Response<Unit>

    // Reports shutdown/boot events with GPS coordinates for theft detection.
    @POST("api/v1/device-activation/{deviceId}/events")
    suspend fun reportDeviceEvent(
        @Path("deviceId") deviceId: String,
        @Body body: Map<String, String>
    ): Response<Unit>

    // Reports GPS location back to server in response to a pull request.
    @POST("api/v1/location/{deviceId}/report")
    suspend fun reportLocation(
        @Path("deviceId") deviceId: String,
        @Header("x-device-token") deviceToken: String,
        @Body body: Map<String, Any>
    ): Response<Unit>

    // Fetches a fresh device JWT for already-enrolled devices that have no stored token.
    @POST("api/v1/device-activation/{deviceId}/refresh-token")
    suspend fun refreshDeviceToken(
        @Path("deviceId") deviceId: String,
        @Body body: Map<String, String>
    ): Response<DeviceTokenRefreshResponse>
}

data class DeviceTokenRefreshResponse(
    @com.google.gson.annotations.SerializedName("success") val success: Boolean,
    @com.google.gson.annotations.SerializedName("device_token") val deviceToken: String?
)

data class DevicePreRegisterRequest(
    val imei: String,
    val fcm_token: String,
    val brand: String,
    val model: String,
    val android_id: String?
)

data class DeviceListResponse(
    val devices: List<DeviceDto>,
    val pagination: PaginationDto
)

data class DeviceDto(
    val id: String,
    val imei: String,
    val model: String?,
    val brand: String?,
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

data class DeviceActivationRequest(
    val activationCode: String,
    val deviceBoundId: String,
    val androidId: String?,
    val serialNumber: String?,
    val socId: String?,
    val deviceName: String,
    val brand: String,
    val model: String,
    val sdk: Int
)

data class DeviceActivationResponse(
    val success: Boolean,
    val mode: String?,
    val deviceId: String?,
    val deviceToken: String?,
    val policy: DeviceActivationPolicy?,
    val message: String?,
    val error: String?
)

data class DeviceActivationPolicy(
    val locationEnabled: Boolean,
    val lockEnabled: Boolean,
    val resetEnabled: Boolean,
    val frpEnabled: Boolean,
    val testMode: Boolean
)
