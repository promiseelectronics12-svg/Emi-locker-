package com.android.simtoolkit.di

import android.content.Context
import androidx.room.Room
import com.android.simtoolkit.data.local.EmiDatabase
import com.android.simtoolkit.data.local.dao.EmiScheduleDao
import com.android.simtoolkit.data.local.PreferencesManager
import com.android.simtoolkit.data.remote.NetworkModule
import com.android.simtoolkit.data.remote.api.ApiService
import com.android.simtoolkit.data.repository.AuthRepository
import com.android.simtoolkit.data.repository.DeviceRepository
import com.android.simtoolkit.device.LockStateManager
import com.android.simtoolkit.overlay.CustomMessageOverlay
import com.android.simtoolkit.overlay.OverlayManager
import com.android.simtoolkit.security.CertificatePinnerConfig
import com.android.simtoolkit.security.CommandVerificationManager
import com.android.simtoolkit.worker.AutoLockScheduler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideEmiDatabase(
        @ApplicationContext context: Context
    ): EmiDatabase {
        return Room.databaseBuilder(
            context,
            EmiDatabase::class.java,
            "emi_locker_db"
        ).build()
    }

    @Provides
    @Singleton
    fun provideEmiScheduleDao(database: EmiDatabase): EmiScheduleDao {
        return database.emiScheduleDao()
    }

    @Provides
    @Singleton
    fun providePreferencesManager(
        @ApplicationContext context: Context
    ): PreferencesManager {
        return PreferencesManager(context)
    }

    @Provides
    @Singleton
    fun provideAutoLockScheduler(
        @ApplicationContext context: Context
    ): AutoLockScheduler {
        return AutoLockScheduler(context)
    }

    @Provides
    @Singleton
    fun provideCommandVerificationManager(
        @ApplicationContext context: Context
    ): CommandVerificationManager {
        return CommandVerificationManager(context)
    }

    @Provides
    @Singleton
    fun provideCertificatePinnerConfig(): CertificatePinnerConfig {
        return CertificatePinnerConfig()
    }

    @Provides
    @Singleton
    fun provideNetworkModule(
        @ApplicationContext context: Context,
        preferencesManager: PreferencesManager,
        commandVerificationManager: CommandVerificationManager,
        certificatePinnerConfig: CertificatePinnerConfig
    ): NetworkModule {
        return NetworkModule(context, preferencesManager, commandVerificationManager, certificatePinnerConfig)
    }

    @Provides
    @Singleton
    fun provideApiService(networkModule: NetworkModule): ApiService {
        return networkModule.apiService
    }

    @Provides
    @Singleton
    fun provideAuthRepository(
        apiService: ApiService,
        preferencesManager: PreferencesManager
    ): AuthRepository {
        return AuthRepository(apiService, preferencesManager)
    }

    @Provides
    @Singleton
    fun provideDeviceRepository(
        apiService: ApiService
    ): DeviceRepository {
        return DeviceRepository(apiService)
    }

    @Provides
    @Singleton
    fun provideOverlayManager(
        @ApplicationContext context: Context,
        preferencesManager: PreferencesManager
    ): OverlayManager {
        return OverlayManager(context, preferencesManager)
    }

    @Provides
    @Singleton
    fun provideLockStateManager(
        @ApplicationContext context: Context,
        preferencesManager: PreferencesManager,
        overlayManager: OverlayManager
    ): LockStateManager {
        return LockStateManager(context, preferencesManager, overlayManager)
    }

    @Provides
    @Singleton
    fun provideCustomMessageOverlay(
        @ApplicationContext context: Context,
        preferencesManager: PreferencesManager
    ): CustomMessageOverlay {
        return CustomMessageOverlay(context, preferencesManager)
    }
}
