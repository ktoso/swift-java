import com.google.gson.Gson
import org.gradle.api.DefaultTask
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.Provider
import org.gradle.api.provider.SetProperty
import org.gradle.api.tasks.IgnoreEmptyDirectories
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.JavaExec
import org.gradle.api.tasks.Nested
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.testing.Test
import org.gradle.internal.extensions.core.serviceOf
import org.gradle.process.ExecOperations
import org.gradle.work.DisableCachingByDefault
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.swiftimport.SwiftImportExtension
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.swiftimport.SwiftPMDependency
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.Serializable
import javax.inject.Inject

class SwiftJavaPlugin : Plugin<Project> {

    override fun apply(target: Project) {
        val project = target

        val swiftPMImportExtension = project.swiftDependenciesExtension()
        val importedModules = project.provider {
            swiftPMImportExtension.spmDependencies.flatMap { it.importedModules.map { it.name } }.toSet()
        }

        val computeLocalPackageDependencyInputFiles = project.registerTask<ComputeLocalPackageDependencyInputFiles>(
            ComputeLocalPackageDependencyInputFiles.TASK_NAME,
        ) {}

        val syntheticImportProjectGeneration = project.registerTask<GenerateSyntheticLinkageImportProject>(
            GenerateSyntheticLinkageImportProject.TASK_NAME,
        ) {
            it.configureWithExtension(swiftPMImportExtension)
            it.syntheticProductType.set(GenerateSyntheticLinkageImportProject.SyntheticProductType.DYNAMIC)
        }

        val fetchSyntheticImportProjectPackages = project.registerTask<FetchSyntheticImportProjectPackages>(
            FetchSyntheticImportProjectPackages.TASK_NAME,
        ) {
            it.dependsOn(syntheticImportProjectGeneration)
            it.syntheticImportProjectRoot.set(syntheticImportProjectGeneration.map { it.syntheticImportProjectRoot.get() })
        }

        // === NEW: Build the synthetic import project with `swift build` ===
        val buildSyntheticImportProject = project.registerTask<BuildSyntheticImportProject>(
            "buildSyntheticImportProject"
        ) {
            it.dependsOn(fetchSyntheticImportProjectPackages)
            it.dependsOn(computeLocalPackageDependencyInputFiles)
            it.syntheticImportProjectRoot.set(syntheticImportProjectGeneration.map { it.syntheticImportProjectRoot.get() })
            it.filesToTrackFromLocalPackages.set(computeLocalPackageDependencyInputFiles.flatMap { it.filesToTrackFromLocalPackages })
            it.hasSwiftPMDependencies.set(project.provider { swiftPMImportExtension.spmDependencies.isNotEmpty() })
        }

        // === NEW: Discover module source directories ===
        val discoverModuleSources = project.registerTask<DiscoverModuleSources>(
            "discoverModuleSources"
        ) {
            it.dependsOn(fetchSyntheticImportProjectPackages)
            it.dependsOn(computeLocalPackageDependencyInputFiles)
            it.importedSwiftModules.set(importedModules)
            it.syntheticImportProjectRoot.set(syntheticImportProjectGeneration.map { it.syntheticImportProjectRoot.get() })
            it.filesToTrackFromLocalPackages.set(computeLocalPackageDependencyInputFiles.flatMap { it.filesToTrackFromLocalPackages })
            it.spmDependencies.set(project.provider { swiftPMImportExtension.spmDependencies.toSet() })
        }

        val execOps = project.serviceOf<ExecOperations>()
        val buildSwiftJava = target.registerTask<BuildSwiftJava>("buildSwiftJava") {}

        val swiftJavaIntermediates = project.layout.buildDirectory.dir("swiftJavaIntermediates")

        val importedModuleToSourcesDump = importedModules.map { modules ->
            modules.map { module ->
                ImportedModuleInfo(
                    module,
                    swiftJavaIntermediates.map { it.dir(module).dir("SwiftWrappers") }.get().asFile,
                    swiftJavaIntermediates.map { it.dir(module).dir("JavaWrappers") }.get().asFile,
                )
            }
        }

        val swiftJavaPath = buildSwiftJava.map { it.outputBinary() }

        val convertSwiftInterfacesIntoJavaSources = target.registerTask<DefaultTask>("convertImportedSwiftModulesIntoJavaSources") {
            it.dependsOn(buildSwiftJava)
            it.dependsOn(discoverModuleSources)
            it.doLast {
                val swiftJavaPath = swiftJavaPath.get()
                val intermediates = swiftJavaIntermediates.get().asFile
                if (intermediates.exists()) { intermediates.deleteRecursively() }
                intermediates.mkdirs()

                val moduleSourcesDir = discoverModuleSources.get().moduleSourcesOutputDir.get().asFile

                importedModuleToSourcesDump.get().forEach { moduleInfo ->
                    val sourcePathFile = moduleSourcesDir.resolve("${moduleInfo.moduleName}.sources")
                    if (!sourcePathFile.exists()) {
                        project.logger.warn("No source path found for module ${moduleInfo.moduleName}, skipping jextract")
                        return@forEach
                    }
                    val sourcePath = sourcePathFile.readText().trim()
                    if (sourcePath.isEmpty()) {
                        project.logger.warn("Empty source path for module ${moduleInfo.moduleName}, skipping jextract")
                        return@forEach
                    }

                    moduleInfo.swiftWrappers.mkdirs()
                    moduleInfo.javaWrappers.mkdirs()

                    execOps.exec {
                        it.commandLine(
                            swiftJavaPath,
                            "jextract",
                            "--swift-module", moduleInfo.moduleName,
                            "--java-package", "com.example.swift.${moduleInfo.moduleName}",
                            "--input-swift", sourcePath,
                            "--output-swift", moduleInfo.swiftWrappers,
                            "--output-java", moduleInfo.javaWrappers,
                        )
                    }
                }
            }
        }

        // === SIMPLIFIED: Generate wrappers compilation package ===
        val wrappersPackage = target.registerTask<GeneratePackageForWrappersCompilation>(GeneratePackageForWrappersCompilation.TASK_NAME) {
            it.dependsOn(convertSwiftInterfacesIntoJavaSources)
            it.configureWithExtension(swiftPMImportExtension)
            it.moduleInfos.set(importedModuleToSourcesDump)
            it.aggregateModuleName.set(GeneratePackageForWrappersCompilation.WRAPPERS_COMPILATION_PROJECT_NAME)
            it.syntheticImportProjectRoot.set(syntheticImportProjectGeneration.map { it.syntheticImportProjectRoot.get() })
            it.swiftJavaRepoPath.set(project.rootDir.absolutePath)
        }

        // === SIMPLIFIED: Compile wrappers with `swift build` ===
        val compileSwiftWrappers = target.registerTask<CompileSwiftWrappers>("compileSwiftWrappers") {
            it.dependsOn(wrappersPackage)
            it.wrappersProjectRoot.set(wrappersPackage.flatMap { it.wrappersProjectRoot })
        }

        syntheticImportProjectGeneration.configure {
            it.directlyImportedSpmModules.set(swiftPMImportExtension.spmDependencies)
        }
        swiftPMImportExtension.spmDependencies.all { dependency ->
            when (dependency) {
                is SwiftPMDependency.Local -> {
                    computeLocalPackageDependencyInputFiles.configure {
                        it.localPackages.add(dependency.path)
                    }
                    fetchSyntheticImportProjectPackages.configure {
                        it.localPackageManifests.from(
                            dependency.path.resolve("Package.swift")
                        )
                    }
                }
                is SwiftPMDependency.Remote -> Unit
            }
        }

        target.pluginManager.withPlugin("java") {
            val sourceSets = target.extensions.getByName("sourceSets") as SourceSetContainer
            val mainSourceSet = sourceSets.getByName("main")
            mainSourceSet.java.srcDir(convertSwiftInterfacesIntoJavaSources.map {
                importedModuleToSourcesDump.get().map {
                    it.javaWrappers
                }
            })

            target.tasks.named("compileJava") {
                it.dependsOn(compileSwiftWrappers)
            }

            fun computeLibraryPath(): String {
                val paths = mutableListOf<String>()
                // Swift runtime paths
                paths.add("/usr/lib/swift")
                // swift build output from the synthetic import project
                val importBinPath = buildSyntheticImportProject.get().binPathFile.get().asFile
                if (importBinPath.exists()) {
                    paths.add(importBinPath.readText().trim())
                }
                // swift build output from the wrappers compilation
                val wrappersBinPath = compileSwiftWrappers.get().binPathFile.get().asFile
                if (wrappersBinPath.exists()) {
                    paths.add(wrappersBinPath.readText().trim())
                }
                // Swift runtime library paths from swiftc -print-target-info
                paths.addAll(getSwiftRuntimeLibraryPaths(target.serviceOf<ExecOperations>()))
                return paths.joinToString(":")
            }

            target.tasks.withType(JavaExec::class.java).configureEach {
                it.dependsOn(compileSwiftWrappers)
                it.doFirst { task ->
                    task as JavaExec
                    task.jvmArgs("--enable-native-access=ALL-UNNAMED")
                    task.systemProperty("java.library.path", computeLibraryPath())
                    task.environment("DYLD_FALLBACK_LIBRARY_PATH", computeLibraryPath())
                }
            }

            target.tasks.withType(Test::class.java) {
                it.dependsOn(compileSwiftWrappers)
                it.doFirst { task ->
                    task as Test
                    task.jvmArgs("--enable-native-access=ALL-UNNAMED")
                    task.systemProperty("java.library.path", computeLibraryPath())
                    task.environment("DYLD_FALLBACK_LIBRARY_PATH", computeLibraryPath())
                }
            }
        }
    }
}

// ==== -----------------------------------------------------------------------
// MARK: Utility functions

internal inline fun <reified T: DefaultTask> Project.registerTask(name: String, crossinline configure: (T) -> Unit) =
    tasks.register(name, T::class.java) {
        configure(it)
    }

internal fun Provider<org.gradle.api.file.RegularFile>.getFile() = get().asFile

internal fun Project.swiftDependenciesExtension(): SwiftImportExtension {
    val existingExtension = project.extensions.findByName(SwiftImportExtension.EXTENSION_NAME)
    if (existingExtension != null) {
        return existingExtension as SwiftImportExtension
    }
    project.extensions.create(
        SwiftImportExtension.EXTENSION_NAME,
        SwiftImportExtension::class.java
    )
    return project.extensions.getByName(SwiftImportExtension.EXTENSION_NAME) as SwiftImportExtension
}

internal fun getSwiftRuntimeLibraryPaths(execOps: ExecOperations): List<String> {
    val stdout = ByteArrayOutputStream()
    execOps.exec {
        it.commandLine("swiftc", "-print-target-info")
        it.standardOutput = stdout
    }
    @Suppress("UNCHECKED_CAST")
    val targetInfo = Gson().fromJson(stdout.toString(), Map::class.java) as Map<String, Any>
    @Suppress("UNCHECKED_CAST")
    val paths = targetInfo["paths"] as? Map<String, Any> ?: return emptyList()
    @Suppress("UNCHECKED_CAST")
    return (paths["runtimeLibraryPaths"] as? List<String>) ?: emptyList()
}

internal data class ImportedModuleInfo(
    @get:Input
    val moduleName: String,
    @get:PathSensitive(PathSensitivity.RELATIVE)
    @get:InputDirectory
    val swiftWrappers: File,
    @get:PathSensitive(PathSensitivity.RELATIVE)
    @get:InputDirectory
    val javaWrappers: File,
) : Serializable

// ==== -----------------------------------------------------------------------
// MARK: BuildSwiftJava — builds the swift-java tool itself

@DisableCachingByDefault(because = "Swift build has its own caching")
internal abstract class BuildSwiftJava : DefaultTask() {

    @get:Internal
    val swiftJavaRepoPath = project.rootDir

    @get:InputFile
    protected val manifest get() = swiftJavaRepoPath.resolve("Package.swift")
    @get:InputFile
    protected val lockFile get() = swiftJavaRepoPath.resolve("Package.resolved")
    @get:InputDirectory
    protected val sources get() = swiftJavaRepoPath.resolve("Sources")

    @get:Inject
    protected abstract val execOps: ExecOperations

    @get:OutputFile
    val outputBinary get() = {
        val showBinPathOutput = ByteArrayOutputStream()
        execOps.exec {
            it.workingDir(swiftJavaRepoPath)
            it.commandLine("swift", "build", "--show-bin-path")
            it.standardOutput = showBinPathOutput
        }
        File(showBinPathOutput.toString().lineSequence().first()).resolve("swift-java")
    }

    @TaskAction
    fun build() {
        execOps.exec {
            it.workingDir(swiftJavaRepoPath)
            it.commandLine("swift", "build", "--product", "swift-java")
        }
    }
}

// ==== -----------------------------------------------------------------------
// MARK: GenerateSyntheticLinkageImportProject — generates Package.swift that imports all deps

@DisableCachingByDefault(because = "Fast task, generates Package.swift")
internal abstract class GenerateSyntheticLinkageImportProject : DefaultTask() {

    @get:Input
    abstract val directlyImportedSpmModules: SetProperty<SwiftPMDependency>

    @get:Internal
    val syntheticImportProjectRoot: DirectoryProperty = project.objects.directoryProperty().convention(
        project.layout.buildDirectory.dir("swiftJava/swiftImport")
    )

    @get:OutputDirectory
    protected val projectRootTrackedFiles get() = syntheticImportProjectRoot.get().asFile

    @get:Optional
    @get:Input
    abstract val macosDeploymentVersion: Property<String>

    @get:Input
    abstract val syntheticProductType: Property<SyntheticProductType>

    enum class SyntheticProductType : Serializable {
        DYNAMIC,
        INFERRED,
    }

    fun configureWithExtension(swiftPMImportExtension: SwiftImportExtension) {
        macosDeploymentVersion.set(swiftPMImportExtension.macosDeploymentVersion)
    }

    @TaskAction
    fun generateSwiftPMSyntheticImportProjectAndFetchPackages() {
        val packageRoot = syntheticImportProjectRoot.get().asFile
        generatePackageManifest(
            identifier = SYNTHETIC_IMPORT_TARGET_MAGIC_NAME,
            packageRoot = packageRoot,
            syntheticProductType = syntheticProductType.get(),
            directlyImportedSwiftPMDependencies = directlyImportedSpmModules.get(),
        )
    }

    private fun generatePackageManifest(
        identifier: String,
        packageRoot: File,
        syntheticProductType: SyntheticProductType,
        directlyImportedSwiftPMDependencies: Set<SwiftPMDependency>,
    ) {
        val repoDependencies = directlyImportedSwiftPMDependencies.map { importedPackage ->
            buildString {
                appendLine(".package(")
                when (importedPackage) {
                    is SwiftPMDependency.Remote -> {
                        when (val repository = importedPackage.repository) {
                            is SwiftPMDependency.Remote.Repository.Id -> {
                                appendLine("  id: \"${repository.value}\",")
                            }
                            is SwiftPMDependency.Remote.Repository.Url -> {
                                appendLine("  url: \"${repository.value}\",")
                            }
                        }
                        when (val version = importedPackage.version) {
                            is SwiftPMDependency.Remote.Version.Exact -> appendLine("  exact: \"${version.value}\",")
                            is SwiftPMDependency.Remote.Version.From -> appendLine("  from: \"${version.value}\",")
                            is SwiftPMDependency.Remote.Version.Range -> appendLine("  \"${version.from}\"...\"${version.through}\",")
                            is SwiftPMDependency.Remote.Version.Branch -> appendLine("  branch: \"${version.value}\",")
                            is SwiftPMDependency.Remote.Version.Revision -> appendLine("  revision: \"${version.value}\",")
                        }
                    }
                    is SwiftPMDependency.Local -> {
                        appendLine("  path: \"${importedPackage.path.path}\",")
                    }
                }
                if (importedPackage.traits.isNotEmpty()) {
                    val traitsString = importedPackage.traits.joinToString(", ") { "\"${it}\"" }
                    appendLine("  traits: [${traitsString}],")
                }
                appendLine("),")
            }
        }

        val targetDependencies = directlyImportedSwiftPMDependencies.flatMap { dep -> dep.products.map { it to dep.packageName } }.map {
            buildString {
                appendLine(".product(")
                appendLine("  name: \"${it.first.name}\",")
                appendLine("  package: \"${it.second}\",")
                val platformConstraints = it.first.platformConstraints
                if (platformConstraints != null) {
                    val platformsString = platformConstraints.joinToString(", ") { ".${it.swiftEnumName}" }
                    appendLine("  condition: .when(platforms: [${platformsString}]),")
                }
                appendLine("),")
            }
        }

        val platforms = listOf(".macOS(\"${macosDeploymentVersion.get()}\"),")

        val productType = when (syntheticProductType) {
            SyntheticProductType.DYNAMIC -> ".dynamic"
            SyntheticProductType.INFERRED -> ".none"
        }

        val manifest = packageRoot.resolve(MANIFEST_NAME)
        manifest.also {
            it.parentFile.mkdirs()
        }.writeText(
            buildString {
                appendLine("// swift-tools-version: 6.0")
                appendLine("import PackageDescription")
                appendLine("let package = Package(")
                appendLine("  name: \"$identifier\",")
                appendLine("  platforms: [")
                platforms.forEach { appendLine("    $it")}
                appendLine("  ],")
                appendLine(
                    """
                        products: [
                            .library(
                                name: "$identifier",
                                type: ${productType},
                                targets: ["$identifier"]
                            ),
                        ],
                    """.replaceIndent("  ")
                )
                appendLine("  dependencies: [")
                repoDependencies.forEach { appendLine(it.replaceIndent("    ")) }
                appendLine("  ],")
                appendLine("  targets: [")
                appendLine("    .target(")
                appendLine("      name: \"$identifier\",")
                appendLine("      dependencies: [")
                targetDependencies.forEach { appendLine(it.replaceIndent("        ")) }
                appendLine("      ],")
                appendLine("    ),")
                appendLine("  ]")
                appendLine(")")
            }
        )

        val swiftSource = "Sources/${identifier}/${identifier}.swift"
        packageRoot.resolve(swiftSource).also {
            it.parentFile.mkdirs()
        }.writeText("")
    }

    companion object {
        const val TASK_NAME = "generateSyntheticLinkageSwiftPMImportProject"
        const val SYNTHETIC_IMPORT_TARGET_MAGIC_NAME = "_internal_linkage_SwiftPMImport"
        const val MANIFEST_NAME = "Package.swift"
    }
}

// ==== -----------------------------------------------------------------------
// MARK: FetchSyntheticImportProjectPackages — runs `swift package resolve`

@DisableCachingByDefault(because = "Network-dependent")
internal abstract class FetchSyntheticImportProjectPackages : DefaultTask() {

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val localPackageManifests: ConfigurableFileCollection

    @get:Internal
    val syntheticImportProjectRoot: DirectoryProperty = project.objects.directoryProperty()

    @get:IgnoreEmptyDirectories
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val inputManifests
        get() = syntheticImportProjectRoot
            .asFileTree
            .matching {
                it.include("**/Package.swift")
            }

    @get:OutputFile
    val lockFile = syntheticImportProjectRoot.file("Package.resolved")

    @get:Inject
    protected abstract val execOps: ExecOperations

    @TaskAction
    fun fetchPackages() {
        val projectRoot = syntheticImportProjectRoot.get().asFile
        execOps.exec {
            it.workingDir(projectRoot)
            it.commandLine("swift", "package", "resolve")
        }
    }

    companion object {
        const val TASK_NAME = "fetchSyntheticImportProjectPackages"
    }
}

// ==== -----------------------------------------------------------------------
// MARK: BuildSyntheticImportProject — runs `swift build` on the synthetic project

@DisableCachingByDefault(because = "Swift build has its own caching")
internal abstract class BuildSyntheticImportProject : DefaultTask() {

    @get:Internal
    abstract val syntheticImportProjectRoot: DirectoryProperty

    @get:Input
    abstract val hasSwiftPMDependencies: Property<Boolean>

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val filesToTrackFromLocalPackages: RegularFileProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    protected val localPackageSources get() = filesToTrackFromLocalPackages.map {
        it.asFile.readLines().filter { it.isNotEmpty() }.map { File(it) }
    }

    @get:OutputFile
    val binPathFile: RegularFileProperty = project.objects.fileProperty().convention(
        project.layout.buildDirectory.file("swiftJava/syntheticImportBinPath.txt")
    )

    @get:Inject
    protected abstract val execOps: ExecOperations

    @TaskAction
    fun build() {
        if (!hasSwiftPMDependencies.get()) {
            binPathFile.get().asFile.also { it.parentFile.mkdirs() }.writeText("")
            return
        }

        val projectRoot = syntheticImportProjectRoot.get().asFile

        // Build the synthetic project
        execOps.exec {
            it.workingDir(projectRoot)
            it.commandLine("swift", "build")
        }

        // Capture the bin path
        val stdout = ByteArrayOutputStream()
        execOps.exec {
            it.workingDir(projectRoot)
            it.commandLine("swift", "build", "--show-bin-path")
            it.standardOutput = stdout
        }
        val binPath = stdout.toString().trim()
        binPathFile.get().asFile.also { it.parentFile.mkdirs() }.writeText(binPath)
    }
}

// ==== -----------------------------------------------------------------------
// MARK: DiscoverModuleSources — finds source directories for imported modules

@DisableCachingByDefault(because = "Depends on SwiftPM checkout layout")
internal abstract class DiscoverModuleSources : DefaultTask() {

    @get:Input
    abstract val importedSwiftModules: SetProperty<String>

    @get:Internal
    abstract val syntheticImportProjectRoot: DirectoryProperty

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val filesToTrackFromLocalPackages: RegularFileProperty

    @get:Input
    abstract val spmDependencies: SetProperty<SwiftPMDependency>

    @get:OutputDirectory
    val moduleSourcesOutputDir: DirectoryProperty = project.objects.directoryProperty().convention(
        project.layout.buildDirectory.dir("swiftJava/moduleSources")
    )

    @get:Inject
    protected abstract val execOps: ExecOperations

    @TaskAction
    fun discoverSources() {
        val outputDir = moduleSourcesOutputDir.get().asFile
        if (outputDir.exists()) outputDir.deleteRecursively()
        outputDir.mkdirs()

        val modules = importedSwiftModules.get()
        val projectRoot = syntheticImportProjectRoot.get().asFile
        val checkoutsDir = projectRoot.resolve(".build/checkouts")

        // Build a map from package name -> local path for local deps
        val localPackagePaths = mutableMapOf<String, File>()
        spmDependencies.get().forEach { dep ->
            if (dep is SwiftPMDependency.Local) {
                localPackagePaths[dep.packageName] = dep.path
            }
        }

        for (moduleName in modules) {
            val sourcePath = findModuleSourcePath(moduleName, checkoutsDir, localPackagePaths)
            if (sourcePath != null) {
                outputDir.resolve("${moduleName}.sources").writeText(sourcePath)
            } else {
                project.logger.warn("Could not find source path for module: $moduleName")
            }
        }
    }

    private fun findModuleSourcePath(
        moduleName: String,
        checkoutsDir: File,
        localPackagePaths: Map<String, File>
    ): String? {
        // First: check local package paths
        for ((_, packagePath) in localPackagePaths) {
            val candidateSources = packagePath.resolve("Sources/$moduleName")
            if (candidateSources.isDirectory && hasSwiftFiles(candidateSources)) {
                return candidateSources.absolutePath
            }
        }

        // Second: check .build/checkouts/{package}/Sources/{module}/
        if (checkoutsDir.isDirectory) {
            checkoutsDir.listFiles()?.forEach { packageDir ->
                if (packageDir.isDirectory) {
                    val candidateSources = packageDir.resolve("Sources/$moduleName")
                    if (candidateSources.isDirectory && hasSwiftFiles(candidateSources)) {
                        return candidateSources.absolutePath
                    }
                }
            }
        }

        // Third: use `swift package describe --type json` on the synthetic project
        return findModuleSourcePathViaPackageDescribe(moduleName)
    }

    @Suppress("UNCHECKED_CAST")
    private fun findModuleSourcePathViaPackageDescribe(moduleName: String): String? {
        val projectRoot = syntheticImportProjectRoot.get().asFile
        val stdout = ByteArrayOutputStream()
        try {
            execOps.exec {
                it.workingDir(projectRoot)
                it.commandLine("swift", "package", "describe", "--type", "json")
                it.standardOutput = stdout
                // Strip SDK env vars that confuse the manifest compiler
                it.environment.keys.removeAll { it.startsWith("SDK") }
            }
        } catch (e: Exception) {
            project.logger.warn("Failed to run swift package describe: ${e.message}")
            return null
        }

        try {
            val packageJson = Gson().fromJson(stdout.toString(), Map::class.java) as Map<String, Any>
            val targets = packageJson["targets"] as? List<Map<String, Any>> ?: return null
            for (target in targets) {
                val name = target["name"] as? String ?: continue
                if (name == moduleName) {
                    val path = target["path"] as? String ?: continue
                    val resolvedPath = if (File(path).isAbsolute) File(path) else projectRoot.resolve(path)
                    if (resolvedPath.isDirectory) {
                        return resolvedPath.absolutePath
                    }
                }
            }
        } catch (e: Exception) {
            project.logger.warn("Failed to parse swift package describe output: ${e.message}")
        }
        return null
    }

    private fun hasSwiftFiles(dir: File): Boolean {
        return dir.walkTopDown().any { it.isFile && (it.extension == "swift" || it.extension == "swiftinterface") }
    }
}

// ==== -----------------------------------------------------------------------
// MARK: GeneratePackageForWrappersCompilation — generates Package.swift for wrappers

@DisableCachingByDefault(because = "Fast task, generates Package.swift")
internal abstract class GeneratePackageForWrappersCompilation : DefaultTask() {

    @get:Nested
    abstract val moduleInfos: ListProperty<ImportedModuleInfo>

    @get:Internal
    abstract val syntheticImportProjectRoot: DirectoryProperty

    @get:Internal
    abstract val swiftJavaRepoPath: Property<String>

    @get:Internal
    val wrappersProjectRoot: DirectoryProperty = project.objects.directoryProperty().convention(
        project.layout.buildDirectory.dir("swiftJava/swiftImportWrappersCompilation")
    )

    @get:Input
    abstract val aggregateModuleName: Property<String>

    @get:Optional
    @get:Input
    abstract val macosDeploymentVersion: Property<String>

    @get:OutputFile
    protected val manifest get() = wrappersProjectRoot.get().asFile.resolve("Package.swift")
    @get:OutputDirectory
    protected val sources get() = wrappersProjectRoot.get().asFile.resolve("Sources")

    @get:Inject
    protected abstract val fsOps: FileSystemOperations

    fun configureWithExtension(swiftPMImportExtension: SwiftImportExtension) {
        macosDeploymentVersion.set(swiftPMImportExtension.macosDeploymentVersion)
    }

    @TaskAction
    fun generatePackageForWrappersCompilation() {
        val packageRoot = wrappersProjectRoot.get().asFile

        val platforms = listOf(".macOS(\"${macosDeploymentVersion.get()}\"),")
        val importProjectPath = syntheticImportProjectRoot.get().asFile.absolutePath
        val swiftJavaPath = swiftJavaRepoPath.get()

        val wrapperModules = mutableListOf<String>()
        val targets = mutableListOf<String>()
        val products = mutableListOf<String>()

        moduleInfos.get().forEach {
            val wrapperName = "${it.moduleName}_Wrappers"
            wrapperModules.add(wrapperName)
            targets.add(
                """
                    .target(
                        name: "${wrapperName}",
                        dependencies: [
                            .product(
                                name: "${GenerateSyntheticLinkageImportProject.SYNTHETIC_IMPORT_TARGET_MAGIC_NAME}",
                                package: "swiftImport"
                            ),
                            .product(
                                name: "SwiftRuntimeFunctions",
                                package: "swift-java"
                            ),
                        ],
                        swiftSettings: [
                            .swiftLanguageMode(.v5),
                        ]
                    ),
                """.trimIndent()
            )
            products.add(
                """
                    .library(
                        name: "${wrapperName}",
                        type: .dynamic,
                        targets: ["${wrapperName}"]
                    ),
                """.trimIndent()
            )
        }

        // Aggregate target depends on all wrapper modules
        val dependenciesString = wrapperModules.joinToString(", ") { "\"${it}\"" }
        targets.add(
            """
                .target(
                    name: "${aggregateModuleName.get()}",
                    dependencies: [${dependenciesString}]
                ),
            """.trimIndent()
        )
        products.add(
            """
                .library(
                    name: "${aggregateModuleName.get()}",
                    type: .dynamic,
                    targets: ["${aggregateModuleName.get()}"]
                ),
            """.trimIndent()
        )

        val manifestFile = packageRoot.resolve(MANIFEST_NAME)
        manifestFile.also {
            it.parentFile.mkdirs()
        }.writeText(
            buildString {
                appendLine("// swift-tools-version: 6.0")
                appendLine("import PackageDescription")
                appendLine("let package = Package(")
                appendLine("  name: \"$WRAPPERS_COMPILATION_PROJECT_NAME\",")
                appendLine("  platforms: [")
                platforms.forEach { appendLine("    $it")}
                appendLine("  ],")
                appendLine("  products: [")
                products.forEach { appendLine("    $it")}
                appendLine("  ],")
                appendLine("  dependencies: [")
                appendLine("    .package(path: \"${importProjectPath}\"),")
                appendLine("    .package(name: \"swift-java\", path: \"${swiftJavaPath}\"),")
                appendLine("  ],")
                appendLine("  targets: [")
                targets.forEach { appendLine("    $it") }
                appendLine("  ]")
                appendLine(")")
            }
        )

        // Copy Swift wrapper sources into place and add module import
        moduleInfos.get().forEach { module ->
            val swiftSource = "Sources/${module.moduleName}_Wrappers"
            val wrapperPath = packageRoot.resolve(swiftSource).also {
                it.parentFile.mkdirs()
            }
            fsOps.sync {
                it.from(module.swiftWrappers)
                it.into(wrapperPath)
            }
            // The generated thunks reference types from the original module but don't
            // import it (in normal jextract they compile within the same module).
            // Add the import to each Swift file so they compile in a separate module.
            wrapperPath.walkTopDown().filter { it.extension == "swift" }.forEach { swiftFile ->
                val content = swiftFile.readText()
                if (!content.contains("import ${module.moduleName}")) {
                    swiftFile.writeText("import ${module.moduleName}\n$content")
                }
            }
        }

        // Create empty source for aggregate target
        packageRoot.resolve("Sources/${aggregateModuleName.get()}/${aggregateModuleName.get()}.swift").also {
            it.parentFile.mkdirs()
        }.writeText("")
    }

    companion object {
        const val TASK_NAME = "generateSwiftWrappersCompilationPackage"
        const val WRAPPERS_COMPILATION_PROJECT_NAME = "SwiftWrappersCompilation"
        const val MANIFEST_NAME = "Package.swift"
    }
}

// ==== -----------------------------------------------------------------------
// MARK: CompileSwiftWrappers — builds the wrappers project with `swift build`

@DisableCachingByDefault(because = "Swift build has its own caching")
internal abstract class CompileSwiftWrappers : DefaultTask() {

    @get:Internal
    abstract val wrappersProjectRoot: DirectoryProperty

    @get:OutputFile
    val binPathFile: RegularFileProperty = project.objects.fileProperty().convention(
        project.layout.buildDirectory.file("swiftJava/wrappersBinPath.txt")
    )

    @get:Inject
    protected abstract val execOps: ExecOperations

    @TaskAction
    fun build() {
        val projectRoot = wrappersProjectRoot.get().asFile

        execOps.exec {
            it.workingDir(projectRoot)
            it.commandLine("swift", "build")
        }

        val stdout = ByteArrayOutputStream()
        execOps.exec {
            it.workingDir(projectRoot)
            it.commandLine("swift", "build", "--show-bin-path")
            it.standardOutput = stdout
        }
        val binPath = stdout.toString().trim()
        binPathFile.get().asFile.also { it.parentFile.mkdirs() }.writeText(binPath)
    }
}

// ==== -----------------------------------------------------------------------
// MARK: ComputeLocalPackageDependencyInputFiles

@DisableCachingByDefault(because = "Fast file-listing task")
internal abstract class ComputeLocalPackageDependencyInputFiles : DefaultTask() {

    @get:Input
    val localPackages: SetProperty<File> = project.objects.setProperty(File::class.java)

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    protected val manifests get() = localPackages.map { it.map { it.resolve("Package.swift") } }

    @get:OutputFile
    val filesToTrackFromLocalPackages: RegularFileProperty = project.objects.fileProperty().convention(
        project.layout.buildDirectory.file("swiftJava/swiftImportFilesToTrackFromLocalPackages")
    )

    @get:Inject
    protected abstract val execOps: ExecOperations

    @TaskAction
    fun computeFiles() {
        val localPackageFiles = localPackages.get().flatMap { packageRoot ->
            listOf(
                packageRoot.resolve("Package.swift")
            ) + findLocalPackageSources(packageRoot)
        }.map {
            it.path
        }
        filesToTrackFromLocalPackages.getFile().writeText(
            localPackageFiles.joinToString("\n")
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun findLocalPackageSources(path: File): List<File> {
        val jsonBuffer = ByteArrayOutputStream()
        execOps.exec { exec ->
            exec.workingDir(path)
            exec.standardOutput = jsonBuffer
            exec.commandLine("swift", "package", "describe", "--type", "json")
            exec.environment.keys.filter {
                it.startsWith("SDK")
            }.forEach {
                exec.environment.remove(it)
            }
        }
        val packageJson = Gson().fromJson(
            jsonBuffer.toString(), Map::class.java
        ) as Map<String, Any>
        val targets = packageJson["targets"] as List<Map<String, Any>>
        val relativeSourceRootPaths = targets
            .filter {
                val moduleType = it["module_type"]
                moduleType == "SwiftTarget" || moduleType == "ClangTarget"
            }
            .map {
                it["path"] as String
            }
        return relativeSourceRootPaths.map {
            path.resolve(it)
        }
    }

    companion object {
        const val TASK_NAME = "computeLocalPackageDependencyInputFiles"
    }
}

internal const val SYNTHETIC_IMPORT_TARGET_MAGIC_NAME = "_internal_linkage_SwiftPMImport"
