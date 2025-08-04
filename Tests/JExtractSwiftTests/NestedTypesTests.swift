//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import JExtractSwiftLib
import Testing
import JavaKitConfigurationShared

final class NestedTypesTests {
  let input =
    """
    import Swift

    public struct TopLevel {}

    public extension TopLevel { 
        public struct NestedStruct {
            public func example() -> Int { 12 }
        }

        public enum Errors: Error {
        case someError
        }
    }
    """

  @Test("Nested types")
  func nested_enum() throws {
    var config = Configuration()
    config.logLevel = .trace

    try assertOutput(
      input: input, 
      config: config,
      .ffm, .swift,
      swiftModuleName: "FakeModule",
      detectChunkByInitialLines: 1,
      expectedChunks:
      [
        """
        @_cdecl("swiftjava_getType_FakeModule_TopLevel")
        public func swiftjava_getType_FakeModule_TopLevel() -> UnsafeMutableRawPointer /* Any.Type */ {
          return unsafeBitCast(TopLevel.self, to: UnsafeMutableRawPointer.self)
        }
        """,
        """
        @_cdecl("swiftjava_getType_FakeModule_TopLevel.NestedStruct")
        public func swiftjava_getType_FakeModule_TopLevel.NestedStruct() -> UnsafeMutableRawPointer /* Any.Type */ {
          return unsafeBitCast(TopLevel.NestedStruct.self, to: UnsafeMutableRawPointer.self)
        }
        """,
        """
        @_cdecl("swiftjava_getType_FakeModule_TopLevel.Errors")
        public func swiftjava_getType_FakeModule_TopLevel.Errors() -> UnsafeMutableRawPointer /* Any.Type */ {
          return unsafeBitCast(TopLevel.Errors.self, to: UnsafeMutableRawPointer.self)
        }
        """
      ]
    )
  }

  @Test("Analysis should post process nesting")
  func nesting_analysis() throws {
    var config = Configuration()
    config.swiftModule = "FakeModule"
    let translator = Swift2JavaTranslator(config: config)

    try! translator.analyze(file: "/fake/Fake.swiftinterface", text: input)
    
    guard let topLevel = translator.importedGlobalFuncs.first else {
      #expect(false, "Expected top level type to be detected")
      return
    }

    translator.
    config

  }

  @Test("Nested types: extracted as nested java type")
  func nested_type_generated() throws {
    var config = Configuration()
    config.logLevel = .trace

    try assertOutput(
      input: input, 
      config: config,
      .ffm, .swift,
      swiftModuleName: "FakeModule",
      detectChunkByInitialLines: 1,
      expectedChunks:
      [
        """
        final class TopLevel extends FFMSwiftInstance implements SwiftValue {
          static final class NestedStruct extends FFMSwiftInstance implements SwiftValue {
          }
        }
        """
      ]
    )
  }

}
