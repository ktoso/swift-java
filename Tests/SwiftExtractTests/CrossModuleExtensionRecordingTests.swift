//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import SwiftExtract
import Testing

/// Extensions on nominal types owned by another module used to be discarded whole: both
/// the conformances they added and the members they contributed. These verify they are
/// recorded now, and equally that recording them does not turn the foreign type into an
/// emission target.
@Suite("Recording cross-module extensions")
struct CrossModuleExtensionRecordingSuite {

  // ==== -----------------------------------------------------------------------
  // MARK: Conformance-only extensions

  @Test func conformanceOnStdlibTypeIsRecorded() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension String: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.extendedType.fullyQualifiedName == "Swift.String")
    #expect(recorded.addedConformances.map(\.description) == ["Labelable"])
    #expect(recorded.members.isEmpty)
    #expect(!recorded.isConditional)
  }

  /// The compatibility guarantee. Recording a foreign type must not register it in
  /// `extractedTypes`, which every generator treats as its emission worklist
  @Test func recordingDoesNotMakeTheForeignTypeAnEmissionTarget() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension String: Labelable {}
          extension Int { public func doubled() -> Int { self * 2 } }
          """
        )
      ],
      moduleName: "TestModule"
    )

    #expect(result.extractedTypes["String"] == nil)
    #expect(result.extractedTypes["Int"] == nil)
    // Only the module's own protocol is an emission target
    #expect(result.extractedTypes.keys.sorted() == ["Labelable"])
  }

  @Test func moduleSelectorSpellingResolvesTheSameWay() throws {
    // `.swiftinterface` files spell foreign types with a module selector. SwiftExtract
    // ignores the selector and resolves by leaf name, which is what makes the
    // FoundationModels case work at all
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension Swift::String: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.extendedType.fullyQualifiedName == "Swift.String")
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Member-contributing extensions

  @Test func membersOnStdlibTypeAreRecorded() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          extension Int {
            public func doubled() -> Int { self * 2 }
            public var isZero: Bool { self == 0 }
          }
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.extendedType.fullyQualifiedName == "Swift.Int")
    #expect(recorded.addedConformances.isEmpty)
    #expect(recorded.members.methods.map(\.name) == ["doubled"])
    #expect(recorded.members.variables.contains { $0.name == "isZero" })
  }

  @Test func conformanceAndMembersAreBothRecorded() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension String: Labelable {
            public func shout() -> String { self }
          }
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.addedConformances.map(\.description) == ["Labelable"])
    #expect(recorded.members.methods.map(\.name) == ["shout"])
  }

  /// Two extensions on the same foreign type both land, and are retrievable together
  @Test func multipleExtensionsOnOneTypeAccumulate() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          public protocol Shoutable {}
          extension String: Labelable {}
          extension String: Shoutable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let string = SwiftNominalIdentity(moduleName: "Swift", typeName: SwiftQualifiedTypeName("String"))
    let onString = result.crossModuleExtensions.extensions(of: string)
    #expect(onString.count == 2)
    #expect(onString.flatMap { $0.addedConformances.map(\.description) } == ["Labelable", "Shoutable"])
    #expect(result.crossModuleExtensions.extendedTypes.map(\.fullyQualifiedName) == ["Swift.String"])
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Conditional extensions

  /// A conditional conformance on a foreign generic. Recording happens before the
  /// `where`-clause handling that governs specialization matching, so this survives, and
  /// it is marked conditional so a consumer cannot mistake it for unconditional
  @Test func conditionalConformanceOnStdlibGenericIsRecordedAsConditional() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension Array: Labelable where Element: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.extendedType.fullyQualifiedName == "Swift.Array")
    #expect(recorded.addedConformances.map(\.description) == ["Labelable"])
    #expect(recorded.isConditional)
    #expect(!recorded.requirements.isEmpty)
    // A conformance-constrained extension on an *owned* type gets deferred and can reach
    // `extractedTypes` through the specialization flush. A foreign one returns before the
    // deferral, so that path must stay unreachable for it
    #expect(result.extractedTypes["Array"] == nil)
  }

  @Test func conditionalConformanceOnOptionalIsRecorded() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension Optional: Labelable where Wrapped: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.extendedType.fullyQualifiedName == "Swift.Optional")
    #expect(recorded.isConditional)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Foundation types

  @Test func conformanceOnFoundationTypeIsRecorded() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          import Foundation
          public protocol Labelable {}
          extension Date: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let recorded = try #require(result.crossModuleExtensions.all.first)
    #expect(recorded.extendedType.leafName == "Date")
    #expect(recorded.extendedType.moduleName != "TestModule")
    #expect(result.extractedTypes["Date"] == nil)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Unresolvable extended types

  /// Previously these vanished without trace, making an unresolvable import
  /// indistinguishable from an empty extension
  @Test func unresolvableExtendedTypeIsRecordedSeparately() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension SomeTypeThatDoesNotExist: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    #expect(result.crossModuleExtensions.all.isEmpty)
    let unresolved = try #require(result.crossModuleExtensions.unresolved.first)
    #expect(unresolved.extendedTypeDescription == "SomeTypeThatDoesNotExist")
    #expect(result.extractedTypes["SomeTypeThatDoesNotExist"] == nil)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Owned types are untouched

  /// Extensions on the module's own types must behave exactly as before: members merged
  /// onto the type, conformances merged into `inheritedTypes`, nothing recorded as
  /// cross-module
  @Test func ownedTypeExtensionsAreUnaffected() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          public struct Person {}
          extension Person: Labelable {
            public func greet() -> String { "hi" }
          }
          """
        )
      ],
      moduleName: "TestModule"
    )

    #expect(result.crossModuleExtensions.isEmpty)
    let person = try #require(result.extractedTypes["Person"])
    #expect(person.methods.map(\.name) == ["greet"])
    #expect(person.inheritedTypes.map(\.description) == ["Labelable"])
  }

  /// An owned type the user filtered out stays filtered out. Ownership rejection is not
  /// the same as being foreign, and must not be rerouted into the cross-module record
  @Test func filteredOwnedTypeIsNotRecordedAsCrossModule() throws {
    var config = DefaultSwiftExtractConfiguration(swiftModule: "TestModule")
    config.swiftFilterExclude = ["Person"]

    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          public struct Person {}
          extension Person: Labelable {
            public func greet() -> String { "hi" }
          }
          """
        )
      ],
      moduleName: "TestModule",
      config: config
    )

    #expect(result.extractedTypes["Person"] == nil)
    #expect(result.crossModuleExtensions.isEmpty)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: End to end through the conformance query

  /// The motivating case, whole. A stdlib type conforms to a protocol only transitively,
  /// exactly as FoundationModels gives `Int` `PromptRepresentable` by way of `Generable`
  @Test func stdlibTypeIsFoundThroughTransitiveConformance() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol PromptRepresentable {}
          public protocol ConvertibleToGeneratedContent: PromptRepresentable {}
          public protocol Generable: ConvertibleToGeneratedContent {}

          extension String: PromptRepresentable {}
          extension Int: Generable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let promptRepresentable = SwiftNominalIdentity(
      moduleName: "TestModule",
      typeName: SwiftQualifiedTypeName("PromptRepresentable")
    )
    let conformers = result.typesConforming(to: promptRepresentable)
    let byName = Dictionary(uniqueKeysWithValues: conformers.map { ($0.type.fullyQualifiedName, $0) })

    // Direct
    let string = try #require(byName["Swift.String"])
    #expect(string.derivation == .stated)
    #expect(!string.isConditional)

    // Two hops of protocol inheritance
    let int = try #require(byName["Swift.Int"])
    guard case .inherited(let via) = int.derivation else {
      Issue.record("expected Int's conformance to be inherited, got \(int.derivation)")
      return
    }
    #expect(via.map(\.leafName) == ["Generable", "ConvertibleToGeneratedContent"])
  }

  /// A conditional conformance surfaces from the query still marked conditional, so a
  /// consumer that cannot evaluate the requirement can decline it
  @Test func conditionalConformanceSurfacesAsConditionalFromTheQuery() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Labelable {}
          extension String: Labelable {}
          extension Array: Labelable where Element: Labelable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let labelable = SwiftNominalIdentity(
      moduleName: "TestModule",
      typeName: SwiftQualifiedTypeName("Labelable")
    )
    let conformers = result.typesConforming(to: labelable)
    let byName = Dictionary(uniqueKeysWithValues: conformers.map { ($0.type.fullyQualifiedName, $0) })

    #expect(try #require(byName["Swift.String"]).isConditional == false)
    #expect(try #require(byName["Swift.Array"]).isConditional == true)
  }
}
