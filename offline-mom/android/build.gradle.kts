// Release-blocker fix (B1, R-48): must run before any subproject's own
// build.gradle is parsed, since flutter_tesseract_ocr's bundled
// buildscript{} block calls the now-removed jcenter() method as part of
// Gradle's normal script-compilation step for that subproject - see
// jcenter-compat.gradle's own doc comment for the full investigation.
apply(from = "jcenter-compat.gradle")

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
