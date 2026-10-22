-keepattributes *Annotation*, InnerClasses
-keepclassmembers class com.pufy.app.** { @android.webkit.JavascriptInterface <methods>; }
-keep,includedescriptorclasses class com.pufy.app.**$$serializer { *; }
-keepclassmembers class com.pufy.app.** { *** Companion; }
-keepclasseswithmembers class com.pufy.app.** { kotlinx.serialization.KSerializer serializer(...); }
-dontwarn org.slf4j.**

# Tink (EncryptedSharedPreferences) derleme zamanı açıklamaları
-dontwarn com.google.errorprone.annotations.**
# Mini uygulama köprüsü (window.PufyNative) — R8 adlarını değiştirmesin
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }

# PDFBox Android (Apache 2.0)
-keep class com.tom_roush.pdfbox.** { *; }
-dontwarn com.tom_roush.pdfbox.**
-dontwarn org.bouncycastle.**
