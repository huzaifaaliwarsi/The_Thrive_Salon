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
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            
            // 1. Fix Namespace for older plugins (only if missing)
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val currentNamespace = getNamespace.invoke(android)
                if (currentNamespace == null) {
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, "com.example.${project.name.replace("-", "_")}")
                }
                android.let { ext ->
                if (ext is com.android.build.gradle.BaseExtension) {
                    ext.lintOptions.isAbortOnError = false
                }
            }
            } catch (e: Exception) {
                // Fallback for different AGP versions or if methods don't exist
            }
            // 2. Force SDK Version to match app (Fixes "Missing Android-30" errors)
            try {
                if (android is com.android.build.gradle.BaseExtension) {
                    android.compileSdkVersion(36)
                    android.buildToolsVersion("36.1.0")
                    android.defaultConfig.targetSdkVersion(36)
                }
            } catch (e: Exception) { }

            // 3. Force older versions of libraries that require too new AGP
            project.configurations.all {
                resolutionStrategy.eachDependency {
                    if (requested.group == "androidx.work") {
                        useVersion("2.9.1")
                    }
                    if (requested.group == "androidx.browser" && requested.name == "browser") {
                        useVersion("1.8.0")
                    }
                    if (requested.group == "androidx.core" && (requested.name == "core" || requested.name == "core-ktx")) {
                        useVersion("1.13.0")
                    }
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
