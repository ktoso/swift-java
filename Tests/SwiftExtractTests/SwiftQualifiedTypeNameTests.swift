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
import SwiftParser
import SwiftSyntax
import Testing

/// Verifies `SwiftQualifiedTypeName` parses both dot-form and SE-0491
/// `Module::Type` form, and that `SwiftType` resolves a `Module::Type.Nested`
/// reference through the symbol table.
@Suite("SwiftQualifiedTypeName parsing")
struct SwiftQualifiedTypeNameSuite {

  // ==== -----------------------------------------------------------------------
  // MARK: Init from TypeSyntax

  @Test func plainIdentifier() throws {
    let ty = parseType("Logger")
    let qn = try #require(SwiftQualifiedTypeName(ty))
    #expect(qn.components == ["Logger"])
    #expect(qn.fullName == "Logger")
  }

  @Test func dotQualifiedNested() throws {
    let ty = parseType("Logger.Message")
    let qn = try #require(SwiftQualifiedTypeName(ty))
    #expect(qn.components == ["Logger", "Message"])
    #expect(qn.fullName == "Logger.Message")
  }

  @Test func moduleSelectorOnIdentifier() throws {
    let ty = parseType("Module::Logger")
    let qn = try #require(SwiftQualifiedTypeName(ty))
    #expect(qn.components == ["Logger"])
  }

  @Test func moduleSelectorThenNested() throws {
    let ty = parseType("Module::Logger.Message")
    let qn = try #require(SwiftQualifiedTypeName(ty))
    #expect(qn.components == ["Logger", "Message"])
    #expect(qn.fullName == "Logger.Message")
  }

  @Test func moduleSelectorThenDeeplyNested() throws {
    let ty = parseType("Module::Outer.Mid.Inner")
    let qn = try #require(SwiftQualifiedTypeName(ty))
    #expect(qn.components == ["Outer", "Mid", "Inner"])
  }

  @Test func dotFormModulePrefixIsStrippedWhenModuleNameProvided() throws {
    let ty = parseType("Module.Logger.Message")
    let qn = try #require(SwiftQualifiedTypeName(ty, moduleName: "Module"))
    #expect(qn.components == ["Logger", "Message"])
  }

  @Test func dotFormModulePrefixIsKeptWhenModuleNameMismatches() throws {
    let ty = parseType("Module.Logger.Message")
    let qn = try #require(SwiftQualifiedTypeName(ty, moduleName: "OtherModule"))
    #expect(qn.components == ["Module", "Logger", "Message"])
  }

  @Test func unsupportedRootReturnsNil() throws {
    let ty = parseType("(Int, String)")
    #expect(SwiftQualifiedTypeName(ty) == nil)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: SwiftType resolution of `Module::Type.Nested`

  @Test func resolvesModuleQualifiedNestedTypeInFunctionSignature() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public enum Outer {
            public struct Inner {}
          }
          public func take(_ x: TestModule::Outer.Inner) {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let fn = try #require(result.extractedGlobalFuncs.first { $0.name == "take" })
    let paramType = fn.functionSignature.parameters[0].type
    let nominal = try #require(paramType.asNominalType)
    #expect(nominal.nominalTypeDecl.qualifiedName == "Outer.Inner")
  }

  @Test func resolvesModuleQualifiedTopLevelTypeInFunctionSignature() throws {
    let result = try analyze(
      sources: [
        (
          "/fake/Source.swift",
          """
          public func take(_ x: Swift::Int) {}
          """
        )
      ],
      moduleName: "TestModule"
    )

    let fn = try #require(result.extractedGlobalFuncs.first { $0.name == "take" })
    let paramType = fn.functionSignature.parameters[0].type
    #expect(paramType.asNominalType?.nominalTypeDecl.knownTypeKind == .int)
  }
}

private func parseType(_ source: String) -> TypeSyntax {
  TypeSyntax(stringLiteral: source)
}
