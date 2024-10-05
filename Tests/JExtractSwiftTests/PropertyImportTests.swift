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

import JExtractSwift
import Testing

final class PropertyImportTests {
  let class_interfaceFile =
    """
    // swift-interface-format-version: 1.0
    // swift-compiler-version: Apple Swift version 6.0 effective-5.10 (swiftlang-6.0.0.7.6 clang-1600.0.24.1)
    // swift-module-flags: -target arm64-apple-macosx15.0 -enable-objc-interop -enable-library-evolution -module-name MySwiftLibrary
    import Darwin.C
    import Darwin
    import Swift
    import _Concurrency
    import _StringProcessing
    import _SwiftConcurrencyShims

    public class MySwiftClass {
      public var counter: Int32
    }
    """

  @Test func method_class_helloMemberFunction_self_memorySegment() async throws {
    let st = Swift2JavaTranslator(
      javaPackage: "com.example.swift",
      swiftModuleName: "__FakeModule"
    )
    st.log.logLevel = .trace

    try await st.analyze(swiftInterfacePath: "/fake/__FakeModule/SwiftFile.swiftinterface", text: class_interfaceFile)

    let decl = st.importedTypes["MySwiftClass"]!.variables.first {
      $0.identifier == "counter"
    }!

    let output = CodePrinter.toString { printer in
      st.printFuncDowncallMethod(&printer, decl: decl, selfVariant: .memorySegment)
    }

    assertOutput(
      output,
      expected:
        """
        /**
         * {@snippet lang=swift :
         * public var counter: Int32
         * }
         */
        public static int getCounter(java.lang.foreign.MemorySegment self$) {
            var mh$ = helloMemberFunction.HANDLE;
            try {
                if (TRACE_DOWNCALLS) {
                    traceDowncall(self$);
                }
                mh$.invokeExact(self$);
            } catch (Throwable ex$) {
                throw new AssertionError("should not reach here", ex$);
            }
        }
        """
    )
  }

}
