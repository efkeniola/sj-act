pluginManagement {
    def flutterSdkPath = {
        def properties = new Properties()
        file("local.properties").withInputStream { properties.load(it) }
        def flutterSdkPath = properties.getProperty("flutter.sdk")
        assert flutterSdkPath != null, "flutter.sdk not set in local.properties"
        return flutterSdkPath
    }()

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id "dev.flutter.flutter-plugin-loader" version "1.0.0"
    // AGP 8.13.0 — minimum required is 8.11.1 (raised by current Flutter
    // stable's Gradle plugin). Works with Gradle 8.14.3 and still supports
    // compileSdk 36 (Android 16).
    id "com.android.application" version "8.13.0" apply false
    // Kotlin 2.2.20 — minimum required is 2.2.20 (raised by current Flutter
    // stable's Gradle plugin). 2.1.0 is no longer accepted.
    id "org.jetbrains.kotlin.android" version "2.2.20" apply false
}

include ":app"
