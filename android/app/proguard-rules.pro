# Application + MainActivity are referenced from AndroidManifest.xml so AGP
# keeps them automatically. Compose, DataStore and OkHttp ship consumer
# ProGuard rules. The only app-specific keep we need is for data classes
# that get serialized/deserialized via JSON field names from org.json —
# obfuscating these would break the wire format.

-keep class com.raban.etabli.table.net.** { *; }
-keep class com.raban.etabli.table.data.** { *; }

# Silence transitive warnings for classes we don't ship on Android.
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
