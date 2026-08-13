import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingProperty(name: String): String? =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val requiredSigningProperties = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val hasCompleteReleaseSigning = requiredSigningProperties.all { signingProperty(it) != null }

android {
    namespace = "vn.bizreader.connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "vn.bizreader.connect"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasCompleteReleaseSigning) {
                keyAlias = signingProperty("keyAlias")!!
                keyPassword = signingProperty("keyPassword")!!
                storeFile = file(signingProperty("storeFile")!!)
                storePassword = signingProperty("storePassword")!!
            }
        }
    }

    buildTypes {
        release {
            if (hasCompleteReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.webkit:webkit:1.16.0")
    implementation("com.davemorrissey.labs:subsampling-scale-image-view-androidx:3.10.0")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    testImplementation("junit:junit:4.13.2")
}

val validateReleaseSigning by tasks.registering {
    group = "verification"
    description = "Fails release artifacts when the private upload key is unavailable."
    doLast {
        if (!keystorePropertiesFile.exists()) {
            throw GradleException(
                "Không có android/key.properties. Release APK/AAB không được phép dùng debug signing. " +
                    "Hãy cấu hình upload key; bản debug vẫn build bình thường.",
            )
        }
        val missing = requiredSigningProperties.filter { signingProperty(it) == null }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Thiếu ${missing.joinToString()} trong android/key.properties. " +
                    "Bản debug vẫn build bình thường.",
            )
        }
        val store = file(signingProperty("storeFile")!!)
        if (!store.isFile) {
            throw GradleException("Không tìm thấy upload keystore: ${store.absolutePath}")
        }
    }
}

tasks.configureEach {
    if (name in setOf("assembleRelease", "bundleRelease", "packageRelease", "signReleaseBundle")) {
        dependsOn(validateReleaseSigning)
    }
}
