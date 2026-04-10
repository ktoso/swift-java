plugins {
    kotlin("jvm") version "2.2.21"
    `java-gradle-plugin`
}

dependencies {
    implementation("com.google.code.gson:gson:2.13.2")
}

java {
    targetCompatibility = JavaVersion.VERSION_1_8
}

kotlin {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
}

gradlePlugin {
    plugins {
        create("swift_java_plugin") {
            id = "swift-java-plugin"
            implementationClass = "SwiftJavaPlugin"
        }
    }
}
