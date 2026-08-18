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

// ==== -----------------------------------------------------------------------
// MARK: SwiftNominalIdentity

@Suite("Cross-module extension identity")
struct SwiftNominalIdentitySuite {

  @Test
  func moduleQualificationDistinguishesSameLeafName() {
    let stdlibString = SwiftNominalIdentity(
      moduleName: "Swift",
      typeName: SwiftQualifiedTypeName("String")
    )
    let ownString = SwiftNominalIdentity(
      moduleName: "MyLib",
      typeName: SwiftQualifiedTypeName("String")
    )

    // The whole reason this type exists: extractedTypes is keyed by a
    // module-unqualified name, where these two would collide
    #expect(stdlibString != ownString)
    #expect(stdlibString.qualifiedName == ownString.qualifiedName)
    #expect(stdlibString.fullyQualifiedName == "Swift.String")
    #expect(ownString.fullyQualifiedName == "MyLib.String")
  }

  @Test
  func nestedNamesKeepTheirParentChain() {
    let nested = SwiftNominalIdentity(
      moduleName: "MyLib",
      typeName: SwiftQualifiedTypeName(["GeneratedContent", "Kind"])
    )
    #expect(nested.leafName == "Kind")
    #expect(nested.qualifiedName == "GeneratedContent.Kind")
    #expect(nested.fullyQualifiedName == "MyLib.GeneratedContent.Kind")
  }

  @Test
  func equalIdentitiesHashTogether() {
    let a = SwiftNominalIdentity(moduleName: "Swift", typeName: SwiftQualifiedTypeName("Int"))
    let b = SwiftNominalIdentity(moduleName: "Swift", typeName: SwiftQualifiedTypeName("Int"))
    #expect(a == b)
    #expect(Set([a, b]).count == 1)
  }
}

// ==== -----------------------------------------------------------------------
// MARK: The collection

@Suite("CrossModuleExtensions collection")
struct CrossModuleExtensionsCollectionSuite {

  /// Nothing populates the collection yet, so every existing analysis must observe it
  /// empty. This is the compatibility guarantee for consumers that iterate
  /// `extractedTypes`: no path can have started routing types elsewhere
  @Test
  func existingAnalysesRecordNothing() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Greetable {
            func greet() -> String
          }

          public struct Person: Greetable {
            public func greet() -> String { "hi" }
          }

          extension Person {
            public func shout() -> String { "HI" }
          }
          """
        )
      ],
      moduleName: "TestModule"
    )

    #expect(result.crossModuleExtensions.isEmpty)
    #expect(result.crossModuleExtensions.all.isEmpty)
    #expect(result.crossModuleExtensions.unresolved.isEmpty)
    // The owned type and its extension member are still extracted as before
    let person = try #require(result.extractedTypes["Person"])
    #expect(person.methods.contains { $0.name == "shout" })
  }

  @Test
  func emptyCollectionQueriesReturnEmpty() {
    let extensions = CrossModuleExtensions()
    let string = SwiftNominalIdentity(moduleName: "Swift", typeName: SwiftQualifiedTypeName("String"))
    #expect(extensions.isEmpty)
    #expect(extensions.extensions(of: string).isEmpty)
    #expect(extensions.extendedTypes.isEmpty)
  }
}

// ==== -----------------------------------------------------------------------
// MARK: Transitive conformance query

@Suite("Transitive conformance query")
struct TypesConformingSuite {

  @Test("Conformance is found through protocol inheritance")
  func conformanceIsFoundThroughProtocolInheritance() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol PromptRepresentable {}
          public protocol ConvertibleToGeneratedContent: PromptRepresentable {}
          public protocol Generable: ConvertibleToGeneratedContent {}

          public struct Widget: Generable {}
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

    let widget = try #require(conformers.first { $0.type.leafName == "Widget" })
    guard case .inherited(let via) = widget.derivation else {
      Issue.record("expected Widget's conformance to be inherited, got \(widget.derivation)")
      return
    }
    #expect(via.map(\.leafName) == ["Generable", "ConvertibleToGeneratedContent"])
    #expect(!widget.isConditional)
  }

  @Test
  func directConformanceIsReportedAsStated() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Greetable {}
          public struct Person: Greetable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let greetable = SwiftNominalIdentity(
      moduleName: "TestModule",
      typeName: SwiftQualifiedTypeName("Greetable")
    )
    let person = try #require(result.typesConforming(to: greetable).first { $0.type.leafName == "Person" })
    #expect(person.derivation == .stated)
  }

  @Test
  func unrelatedProtocolYieldsNoConformers() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Greetable {}
          public protocol Unrelated {}
          public struct Person: Greetable {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let unrelated = SwiftNominalIdentity(
      moduleName: "TestModule",
      typeName: SwiftQualifiedTypeName("Unrelated")
    )
    #expect(result.typesConforming(to: unrelated).isEmpty)
  }

  @Test("Cyclic refinement terminates rather than spinning")
  func cyclicRefinementTerminates() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol A: B {}
          public protocol B: A {}
          public struct Thing: A {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let target = SwiftNominalIdentity(moduleName: "TestModule", typeName: SwiftQualifiedTypeName("B"))
    let conformers = result.typesConforming(to: target)
    #expect(conformers.contains { $0.type.leafName == "Thing" })
  }

  @Test("Refining protocols are not surfaced as conformers of what they refine")
  func refiningProtocolsAreNotReportedAsConformers() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public protocol Base {}
          public protocol Refined: Base {}
          public struct Thing: Refined {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let base = SwiftNominalIdentity(moduleName: "TestModule", typeName: SwiftQualifiedTypeName("Base"))
    let conformers = result.typesConforming(to: base)
    #expect(conformers.contains { $0.type.leafName == "Thing" })
    #expect(!conformers.contains { $0.type.leafName == "Refined" })
  }
}
