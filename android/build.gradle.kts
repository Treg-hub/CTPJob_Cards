allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    configurations.all {
        // Force correct tslocationmanager version to override buggy v21 variant
        resolutionStrategy {
            force("com.transistorsoft:tslocationmanager:4.1.6")
        }
    }
}

ext {
    set("playServicesLocationVersion", "21.3.0")
    set("tslocationmanagerVersion", "4.1.6")
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
