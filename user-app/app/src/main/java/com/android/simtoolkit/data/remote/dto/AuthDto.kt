package com.android.simtoolkit.data.remote.dto

import com.google.gson.annotations.SerializedName

data class LoginRequest(
    @SerializedName("nid") val nid: String,
    @SerializedName("password") val password: String
)

data class RegisterRequest(
    @SerializedName("nid") val nid: String,
    @SerializedName("name") val name: String,
    @SerializedName("phone") val phone: String,
    @SerializedName("email") val email: String?,
    @SerializedName("password") val password: String
)

data class AuthResponse(
    @SerializedName("accessToken") val accessToken: String,
    @SerializedName("refreshToken") val refreshToken: String,
    @SerializedName("user") val user: UserDto
)

data class UserDto(
    @SerializedName("id") val id: String,
    @SerializedName("name") val name: String,
    @SerializedName("email") val email: String?,
    @SerializedName("phone") val phone: String,
    @SerializedName("role") val role: String
)

data class ApiError(
    @SerializedName("error") val message: String
)

data class BindingConfirmResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("device_id") val deviceId: String?,
    @SerializedName("device_token") val deviceToken: String?,
    @SerializedName("offline_unlock_secret") val offlineUnlockSecret: String?,
    @SerializedName("dealer_name") val dealerName: String?,
    @SerializedName("dealer_phone") val dealerPhone: String?,
    @SerializedName("emi_schedule") val emiSchedule: EmiScheduleDto?
)

data class EmiScheduleDto(
    @SerializedName("id") val id: String,
    @SerializedName("totalAmount") val totalAmount: Double,
    @SerializedName("downPayment") val downPayment: Double,
    @SerializedName("emiAmount") val emiAmount: Double,
    @SerializedName("duration") val duration: Int,
    @SerializedName("startDate") val startDate: String,
    @SerializedName("graceDays") val graceDays: Int,
    @SerializedName("status") val status: String?,
    @SerializedName("installments") val installments: List<EmiInstallmentDto>
)

data class EmiInstallmentDto(
    @SerializedName("installmentNumber") val installmentNumber: Int,
    @SerializedName("dueDate") val dueDate: String,
    @SerializedName("amount") val amount: Double,
    @SerializedName("status") val status: String
)

data class DeviceEmiScheduleResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("emi_schedule") val emiSchedule: EmiScheduleDto?
)

data class DeviceHeartbeatResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("server_time") val serverTime: String?,
    @SerializedName("dealer_name") val dealerName: String?,
    @SerializedName("dealer_phone") val dealerPhone: String?
)
