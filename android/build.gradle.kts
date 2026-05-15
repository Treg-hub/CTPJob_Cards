plugins {
    // Add the dependency for the Firebase App Distribution Gradle plugin
    // (Enables easy ./gradlew appDistributionUploadRelease commands + future CI/CD)
    id("com.google.firebase.appdistribution") version "5.2.1" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

ext {
    set("playServicesLocationVersion", "21.3.0")
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
