# EMI Locker - ProGuard Rules

# Keep BuildConfig
-keep class com.emilocker.user.BuildConfig { *; }

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
-keep class com.emilocker.user.data.model.** { *; }
-keep class com.emilocker.user.data.remote.** { *; }

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

# Device Admin
-keep class com.emilocker.user.admin.EmiLockerDeviceAdminReceiver { *; }
-keep class com.emilocker.user.service.EmiLockerService { *; }
-keep class com.emilocker.user.fcm.EmiLockerMessagingService { *; }

# Play Integrity
-keep class com.google.android.play.core.integrity.** { *; }

# DataStore
-keep class androidx.datastore.** { *; }

# WorkManager
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker
