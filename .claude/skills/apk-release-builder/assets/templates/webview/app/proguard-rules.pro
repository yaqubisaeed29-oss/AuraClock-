# R8/ProGuard rules. Only used when isMinifyEnabled = true in app/build.gradle.kts.

# The WebView JavaScript bridge is called by name from JS, so R8 must not
# rename or strip its members.
-keepclassmembers class @@PACKAGE@@.MainActivity$Bridge {
    public *;
}
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep line numbers for readable crash reports.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
