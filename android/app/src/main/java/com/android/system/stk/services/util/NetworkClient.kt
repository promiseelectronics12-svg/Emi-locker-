package com.android.system.stk.services.util

import android.content.Context
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

object NetworkClient {

    private const val CONNECT_TIMEOUT = 30L
    private const val READ_TIMEOUT = 30L
    private const val WRITE_TIMEOUT = 30L

    fun createOkHttpClient(context: Context): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(CONNECT_TIMEOUT, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT, TimeUnit.SECONDS)
            .writeTimeout(WRITE_TIMEOUT, TimeUnit.SECONDS)

        builder.addInterceptor { chain ->
            val original = chain.request()
            val requestBuilder = original.newBuilder()
                .header("Content-Type", "application/json")
                .header("Accept", "application/json")
                .header("X-App-Version", "1.0.0")
                .header("X-Platform", "android")
                .method(original.method, original.body)
            chain.proceed(requestBuilder.build())
        }

        if (BuildConfig.DEBUG) {
            val loggingInterceptor = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BODY
            }
            builder.addInterceptor(loggingInterceptor)
        }

        if (!ApiConfig.isDevMode(context)) {
            try {
                val sslContext = SSLContext.getInstance("TLSv1.2")
                val trustManagers = getSystemTrustManagers()
                sslContext.init(null, trustManagers, SecureRandom())
                builder.sslSocketFactory(sslContext.socketFactory, trustManagers.first() as X509TrustManager)
                builder.hostnameVerifier { hostname, session ->
                    val validHosts = listOf("api.emilocker.com", "admin.emilocker.com")
                    validHosts.any { hostname.contains(it) } ||
                        (hostname == "localhost" || hostname == "127.0.0.1")
                }
            } catch (e: Exception) {
                // Rely on system CA store - OkHttpClient uses default trust manager by default
            }
        }

        return builder.build()
    }

    private fun getSystemTrustManagers(): Array<TrustManager> {
        return try {
            val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            tmf.init(null as KeyStore?)
            tmf.trustManagers
        } catch (e: Exception) {
            arrayOf()
        }
    }

    fun createRetrofit(context: Context, baseUrl: String): Retrofit {
        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(createOkHttpClient(context))
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }
}