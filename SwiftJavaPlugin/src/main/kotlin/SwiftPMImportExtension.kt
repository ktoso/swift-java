package org.jetbrains.kotlin.gradle.plugin.mpp.apple.swiftimport

import org.gradle.api.DomainObjectSet
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.model.ObjectFactory
import org.gradle.api.provider.Property
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.swiftimport.SwiftPMDependency.Remote.Repository
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.swiftimport.SwiftPMDependency.Remote.Version
import java.io.File
import java.io.Serializable
import javax.inject.Inject

abstract class SwiftImportExtension @Inject constructor(
    private val objects: ObjectFactory,
) {
    val swiftJavaRepository: RegularFileProperty = objects.fileProperty()
    val macosDeploymentVersion: Property<String> = objects.property(String::class.java).convention("15.0")

    internal abstract val spmDependencies: DomainObjectSet<SwiftPMDependency>

    fun url(value: String): Repository.Url = Repository.Url(value)
    fun id(value: String): Repository.Id = Repository.Id(value)

    fun from(version: String): Version = Version.From(version)
    fun exact(version: String): Version = Version.Exact(version)
    fun revision(version: String): Version = Version.Revision(version)
    fun branch(version: String): Version = Version.Branch(version)
    fun range(from: String, through: String): Version = Version.Range(from, through)

    fun product(
        name: String,
        platforms: Set<SwiftPMDependency.Platform>? = null,
        importedModules: Set<String> = if (platforms != null) setOf(name) else emptySet(),
    ): SwiftPMDependency.Product = SwiftPMDependency.Product(
        name,
        importedModules,
        platforms
    )
    fun iOS(): SwiftPMDependency.Platform = SwiftPMDependency.Platform.iOS
    fun macOS(): SwiftPMDependency.Platform = SwiftPMDependency.Platform.macOS
    fun watchOS(): SwiftPMDependency.Platform = SwiftPMDependency.Platform.watchOS
    fun tvOS(): SwiftPMDependency.Platform = SwiftPMDependency.Platform.tvOS

    fun swiftPackage(
        url: String,
        version: String,
        products: List<String>,
        packageName: String = inferPackageName(url),
        importedModules: List<String> = products,
        traits: Set<String> = setOf(),
    ) {
        spmDependencies.add(
            SwiftPMDependency.Remote(
                repository = Repository.Url(url),
                version = Version.From(version),
                packageName = packageName,
                products = products.map { SwiftPMDependency.Product(it) },
                importedModules = importedModules.map {
                    SwiftPMDependency.ImportedModule(it)
                },
                traits = traits
            )
        )
    }

    fun swiftPackage(
        url: Repository.Url,
        version: Version,
        products: List<SwiftPMDependency.Product>,
        packageName: String = inferPackageName(url.value),
        importedModules: List<String> = products.filter {
            it.platformConstraints == null && it.extraImportedModules.isEmpty()
        }.map { it.name },
        traits: Set<String> = setOf(),
    ) {
        spmDependencies.add(
            SwiftPMDependency.Remote(
                repository = url,
                version = version,
                packageName = packageName,
                products = products,
                importedModules = importedModules.map {
                    SwiftPMDependency.ImportedModule(it)
                } + products.flatMap { product ->
                    product.extraImportedModules.map {
                        SwiftPMDependency.ImportedModule(it, product.platformConstraints)
                    }
                },
                traits = traits,
            )
        )
    }

    fun swiftPackage(
        repository: Repository,
        version: Version,
        products: List<SwiftPMDependency.Product>,
        packageName: String,
        importedModules: List<String> = products.filter {
            it.platformConstraints == null && it.extraImportedModules.isEmpty()
        }.map { it.name },
        traits: Set<String> = setOf(),
    ) {
        spmDependencies.add(
            SwiftPMDependency.Remote(
                repository = repository,
                version = version,
                packageName = packageName,
                products = products,
                importedModules = importedModules.map {
                    SwiftPMDependency.ImportedModule(it)
                } + products.flatMap { product ->
                    product.extraImportedModules.map {
                        SwiftPMDependency.ImportedModule(it, product.platformConstraints)
                    }
                },
                traits = traits,
            )
        )
    }

    fun swiftPackage(
        path: File,
        products: List<String>,
        importedModules: List<String> = products,
        traits: Set<String> = setOf(),
    ) {
        spmDependencies.add(
            SwiftPMDependency.Local(
                path = path,
                packageName = path.name,
                products = products.map { SwiftPMDependency.Product(it) },
                importedModules = importedModules.map {
                    SwiftPMDependency.ImportedModule(it)
                },
                traits = traits,
            )
        )
    }

    fun swiftPackage(
        path: File,
        products: List<SwiftPMDependency.Product>,
        importedModules: List<String> = products.filter {
            it.platformConstraints == null && it.extraImportedModules.isEmpty()
        }.map { it.name },
        traits: Set<String> = setOf(),
        @Suppress("unused", "UNUSED_PARAMETER") javaOverloadsArePain: Boolean = true,
    ) {
        spmDependencies.add(
            SwiftPMDependency.Local(
                path = path,
                packageName = path.name,
                products = products,
                importedModules = importedModules.map {
                    SwiftPMDependency.ImportedModule(it)
                } + products.flatMap { product ->
                    product.extraImportedModules.map {
                        SwiftPMDependency.ImportedModule(it, product.platformConstraints)
                    }
                },
                traits = traits,
            )
        )
    }

    private fun inferPackageName(url: String) = url.split("/").last().split(".git").first()

    companion object {
        const val EXTENSION_NAME = "swiftDependencies"
    }
}

class SwiftPMImport(
    val macosDeploymentVersion: String?,
    val dependencies: Set<SwiftPMDependency>
) : Serializable

sealed class SwiftPMDependency(
    val packageName: String,
    val products: List<Product>,
    val importedModules: List<ImportedModule>,
    val traits: Set<String>,
) : Serializable {
    class Product internal constructor(
        val name: String,
        val extraImportedModules: Set<String> = setOf(),
        val platformConstraints: Set<Platform>? = null,
    ) : Serializable

    class ImportedModule internal constructor(
        val name: String,
        val platformConstraints: Set<Platform>? = null,
    ) : Serializable

    enum class Platform {
        iOS,
        macOS,
        tvOS,
        watchOS;

        val swiftEnumName: String get() = when (this) {
            iOS -> "iOS"
            macOS -> "macOS"
            tvOS -> "tvOS"
            watchOS -> "watchOS"
        }
    }

    class Remote internal constructor(
        val repository: Repository,
        val version: Version,
        products: List<Product>,
        importedModules: List<ImportedModule>,
        packageName: String,
        traits: Set<String>,
    ) : SwiftPMDependency(
        products = products,
        importedModules = importedModules,
        packageName = packageName,
        traits = traits,
    ) {
        sealed class Version : Serializable {
            data class Exact internal constructor(val value: String) : Version()
            data class From internal constructor(val value: String) : Version()
            data class Range internal constructor(val from: String, val through: String) : Version()
            data class Branch internal constructor(val value: String) : Version()
            data class Revision internal constructor(val value: String) : Version()
        }

        sealed class Repository : Serializable {
            data class Id internal constructor(val value: String) : Repository()
            data class Url internal constructor(val value: String) : Repository()
        }
    }

    class Local internal constructor(
        val path: File,
        products: List<Product>,
        importedModules: List<ImportedModule>,
        packageName: String,
        traits: Set<String>,
    ) : SwiftPMDependency(
        products = products,
        importedModules = importedModules,
        packageName = packageName,
        traits = traits,
    )
}
