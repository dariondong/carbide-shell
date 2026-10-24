allprojects {
    repositories {
        google()
        mavenCentral()
    }
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

// Plugin modules pin their own compileSdk; file_picker's transitive
// flutter_plugin_android_lifecycle needs 36. Push every module up to 36 so the
// AAR metadata check passes without editing third-party build files.
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val intType: Class<*> = Int::class.javaPrimitiveType ?: Int::class.javaObjectType
                android.javaClass
                    .getMethod("compileSdkVersion", intType)
                    .invoke(android, 36)
            } catch (_: Exception) {
                // Nothing to do on a non-Android module.
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
