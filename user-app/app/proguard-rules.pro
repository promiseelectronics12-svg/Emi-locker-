# EMI Locker - ProGuard Rules

# Keep BuildConfig
-keep class com.android.simtoolkit.BuildConfig { *; }

# Retrofit
-keepattributes Signature
-keepattributes *Annotation*
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# OkHttp
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }

# Gson
-keep class com.google.gson.** { *; }
-keep class com.android.simtoolkit.data.** { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }

# Device Admin / lock delivery entry points
-keep class com.android.simtoolkit.device.DeviceAdminReceiver { *; }
-keep class com.android.simtoolkit.device.BootCompletedReceiver { *; }
-keep class com.android.simtoolkit.device.ShutdownReceiver { *; }
-keep class com.android.simtoolkit.service.EmiLockerService { *; }
-keep class com.android.simtoolkit.fcm.EmiLockerFcmService { *; }
-keep class com.android.simtoolkit.sms.OfflineUnlockSmsReceiver { *; }
-keep class com.android.simtoolkit.overlay.** { *; }

# Play Integrity
-keep class com.google.android.play.core.integrity.** { *; }

# DataStore
-keep class androidx.datastore.** { *; }

# WorkManager
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker
