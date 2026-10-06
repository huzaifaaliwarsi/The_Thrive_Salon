# Hive
-keep class com.mongodb.** { *; }
-keep class io.hive.** { *; }
-dontwarn io.hive.**

# Dio & Retrofit
-keepattributes Signature, InnerClasses, AnnotationDefault
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class com.example.salon_management_system.** { *; }
-dontwarn okio.**
-dontwarn javax.annotation.**

# Riverpod / State Management
-keep class * extends androidx.lifecycle.ViewModel { *; }
