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

/// Verifies that `SwiftFunctionType` records the `async` / `throws` effect
/// specifiers spelled on a function type, rather than failing to translate the
/// enclosing declaration.
@Suite("Function type effect specifiers")
struct FunctionTypeEffectSpecifierSuite {

  /// Extract the function type of the single parameter of the global func `take`
  private func closureParameterType(_ source: String) throws -> SwiftFunctionType {
    let result = try analyze(
      sources: [("/fake/Source.swift", source)],
      moduleName: "Test"
    )

    let fn = try #require(result.extractedGlobalFuncs.first { $0.name == "take" })
    guard case .function(let fnType) = fn.functionSignature.parameters[0].type else {
      throw TestError("expected .function parameter, got \(fn.functionSignature.parameters[0].type)")
    }
    return fnType
  }

  // ==== -----------------------------------------------------------------------
  // MARK: No effects

  @Test func plainClosureHasNoEffectSpecifiers() throws {
    let fnType = try closureParameterType("public func take(_ cb: () -> Void) {}")

    #expect(fnType.effectSpecifiers.isEmpty)
    #expect(!fnType.isAsync)
    #expect(!fnType.isThrowing)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Single effects

  @Test func asyncClosureRecordsAsync() throws {
    let fnType = try closureParameterType("public func take(_ cb: () async -> Void) {}")

    #expect(fnType.effectSpecifiers == [.async])
    #expect(fnType.isAsync)
    #expect(!fnType.isThrowing)
  }

  @Test func throwingClosureRecordsThrows() throws {
    let fnType = try closureParameterType("public func take(_ cb: () throws -> Void) {}")

    #expect(fnType.effectSpecifiers == [.throws])
    #expect(!fnType.isAsync)
    #expect(fnType.isThrowing)
  }

  @Test func typedThrowsClosureRecordsThrows() throws {
    let fnType = try closureParameterType(
      """
      public struct FishTankError: Error {}
      public func take(_ cb: () throws(FishTankError) -> Void) {}
      """
    )

    #expect(fnType.effectSpecifiers == [.throws])
    #expect(fnType.isThrowing)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Combined effects

  @Test func asyncThrowingClosureRecordsBoth() throws {
    let fnType = try closureParameterType("public func take(_ cb: () async throws -> Void) {}")

    #expect(fnType.effectSpecifiers == [.async, .throws])
    #expect(fnType.isAsync)
    #expect(fnType.isThrowing)
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Description (printed form)

  @Test func descriptionRendersEffectSpecifiers() throws {
    let fnType = try closureParameterType(
      "public func take(_ cb: @escaping (Int) async throws -> Void) {}"
    )

    #expect(fnType.description == "@escaping (Int) async throws -> Void")
  }

  // ==== -----------------------------------------------------------------------
  // MARK: Result position

  @Test func effectsOnReturnedClosureAreRecorded() throws {
    // No parens around the function-typed return: `() -> () async -> Void`
    // parses the return type directly as FunctionTypeSyntax. Adding an outer
    // pair of parens turns it into a 1-tuple wrapping the function type,
    // which is a different shape and not what this test is about.
    let result = try analyze(
      sources: [("/fake/Source.swift", "public func get() -> () async -> Void { fatalError() }")],
      moduleName: "Test"
    )

    let fn = try #require(result.extractedGlobalFuncs.first { $0.name == "get" })
    guard case .function(let fnType) = fn.functionSignature.result.type else {
      Issue.record("expected .function result, got \(fn.functionSignature.result.type)")
      return
    }
    #expect(fnType.effectSpecifiers == [.async])
  }
}

private struct TestError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) {
    self.description = description
  }
}
