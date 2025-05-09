plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Firebase 사용 시 필요
}

android {
    namespace = "com.example.client" // 실제 앱의 namespace로 되어 있는지 확인
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"   

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11 // <--- 변경
        targetCompatibility = JavaVersion.VERSION_11 // <--- 변경
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString() // <--- 변경
    }

    defaultConfig {
        applicationId = "com.example.client" // 실제 앱 ID로 되어 있는지 확인
        minSdk = 23                          // 기존 23 유지
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true               // <--- 수정됨: '=' 사용
    }

    // ndkVersion 설정은 android 블록 직속 또는 defaultConfig 내부 중 한 곳에만 두는 것이 좋습니다.
    // flutter.ndkVersion을 사용하지 않고 특정 버전을 고정하려면 아래 주석을 해제하고 위 android 블록 직속의 ndkVersion은 주석 처리.
    // ndkVersion = "27.0.12077973" // 사용자 파일에 있던 내용, 필요시 활성화

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    // signingConfigs 블록이 없다면 추가 (debug 키는 기본으로 있음)
    // signingConfigs {
    //     getByName("debug") {
    //         // Debug signing configuration
    //     }
    // }
}

flutter {
    source = "../.."
}

dependencies {
    // ... 기존 Kotlin 및 Flutter 관련 의존성들 ...
    // 예: implementation(kotlin("stdlib-jdk8")) // 이미 있을 수 있음

    // Core library desugaring 의존성 추가
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4") // <--- 이 줄 추가! (버전은 최신 안정 버전 확인)

    // ... 기타 Firebase 등 다른 의존성들 ...
}