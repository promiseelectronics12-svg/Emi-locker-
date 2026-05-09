package com.android.simtoolkit.data.remote

import android.content.Context
import android.util.Log
import com.android.simtoolkit.BuildConfig
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.security.CertificatePinnerConfig
import com.android.simtoolkit.security.CommandVerificationManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class NetworkModule @Inject constructor(
    @ApplicationContext private val context: Context,
    private val preferencesManager: PreferencesManager,
    private val commandVerificationManager: CommandVerificationManager,
    private val certificatePinnerConfig: CertificatePinnerConfig
) {
    private val TAG = "NetworkModule"

    private val loggingInterceptor = HttpLoggingInterceptor().apply {
        level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BODY else HttpLoggingInterceptor.Level.HEADERS
    }

    private val authInterceptor = Interceptor { chain ->
        val token = runBlocking {
            preferencesManager.accessToken.first() ?: preferencesManager.deviceToken.first()
        }
        val request = chain.request().newBuilder()
            .apply {
                token?.let {
                    addHeader("Authorization", "Bearer $it")
                }
                addHeader("X-Device-ID", commandVerificationManager.getDeviceBoundIdentifier())
            }
            .build()
        chain.proceed(request)
    }

    private val commandSigningInterceptor = Interceptor { chain ->
        val originalRequest = chain.request()
        val timestamp = System.currentTimeMillis()
        val actionType = originalRequest.url.encodedPath

        try {
            val nonce = runBlocking { commandVerificationManager.generateNonce() }
            val signature = commandVerificationManager.generateSignature(timestamp, nonce, actionType)
            val signedRequest = originalRequest.newBuilder()
                .addHeader("X-Command-Signature", signature)
                .addHeader("X-Command-Timestamp", timestamp.toString())
                .addHeader("X-Command-Nonce", nonce)
                .addHeader("X-Device-Bound-ID", commandVerificationManager.getDeviceBoundIdentifier())
                .build()
            chain.proceed(signedRequest)
        } catch (e: Exception) {
            // Signing is best-effort — proceed without signature headers rather than
            // blocking activation/enrollment requests entirely.
            Log.w(TAG, "Command signing skipped (${e.message}), proceeding unsigned")
            chain.proceed(originalRequest)
        }
    }

    private fun getOkHttpClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .addInterceptor(loggingInterceptor)
            .addInterceptor(authInterceptor)
            .addInterceptor(commandSigningInterceptor)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)

        val certificatePinner = certificatePinnerConfig.buildCertificatePinner()
        if (certificatePinner != null) {
            builder.certificatePinner(certificatePinner)
        }

        return builder.build()
    }

    private val retrofit = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL)
        .client(getOkHttpClient())
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    val apiService: ApiService = retrofit.create(ApiService::class.java)
}
