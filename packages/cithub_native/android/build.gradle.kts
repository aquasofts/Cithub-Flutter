group = "com.aquasofts.cithub_flutter"
version = "1.0.0"

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.squareup.wire")
}

wire {
    sourcePath {
        srcDir("src/main/proto")
    }
    root(
        "tieba.frsPage.FrsPageRequest",
        "tieba.frsPage.FrsPageResponse",
        "tieba.threadList.ThreadListRequest",
        "tieba.threadList.ThreadListResponse",
        "tieba.pbPage.PbPageRequest",
        "tieba.pbPage.PbPageResponse",
        "tieba.pbFloor.PbFloorRequest",
        "tieba.pbFloor.PbFloorResponse",
        "tieba.profile.ProfileRequest",
        "tieba.profile.ProfileResponse",
        "tieba.userPost.UserPostRequest",
        "tieba.userPost.UserPostResponse",
        "tieba.forumRuleDetail.ForumRuleDetailRequest",
        "tieba.forumRuleDetail.ForumRuleDetailResponse",
    )
    kotlin {
        android = true
    }
}

android {
    namespace = "com.aquasofts.cithub_flutter.nativeplugin"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }

    flavorDimensions += "captcha"
    productFlavors {
        create("autoCaptcha") {
            dimension = "captcha"
            buildConfigField("boolean", "CAPTCHA_AUTOFILL_ENABLED", "true")
        }
        create("manualCaptcha") {
            dimension = "captcha"
            buildConfigField("boolean", "CAPTCHA_AUTOFILL_ENABLED", "false")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    "autoCaptchaImplementation"("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("org.jsoup:jsoup:1.21.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-wire:2.11.0")
    implementation("com.squareup.wire:wire-runtime:6.0.0")
    implementation("androidx.core:core-ktx:1.13.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
