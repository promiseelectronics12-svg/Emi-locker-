# Flutter specific
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations

# Dio
-dontwarn dio.**
-keep class dio.** { *; }

# Keep generic signatures
-keepattributes Signature

# For obfuscated classes
-keepnames class * implements java.io.Serializable

# Excel
-keep class com.artofsolving.jodconverter.** { *; }
-keep class org.apache.poi.** { *; }
-keep class org.apache.xmlbeans.** { *; }
-dontwarn org.apache.xmlbeans.**
-dontwarn org.apache.poi.**
-dontwarn org.apache.xmlbeans.**

# QR Code
-keep class net.glxn.qrgen.** { *; }
-keep class net.glxn.qrcode.** { *; }

# Keep model classes
-keep class com.emilocker.dealerapp.shared.models.** { *; }