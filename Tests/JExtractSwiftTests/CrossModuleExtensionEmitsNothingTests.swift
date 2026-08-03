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
// SwiftExtract records extensions on nominal types owned by other modules so that
// downstream generators can learn about them. The Java generators do not consume that
// record, and must keep emitting nothing at all for such extensions: a Java class for
// `String` or `Int` would collide with `java.lang.String` and be nonsense besides.
//
// These are the zero-delta requirement expressed as tests rather than as an argument.
//
//===----------------------------------------------------------------------===//

import JExtractSwiftLib
import SwiftJavaConfigurationShared
import Testing

@Suite("Extensions on other modules' types emit nothing")
struct CrossModuleExtensionEmitsNothingTests {

  /// An owned type alongside foreign extensions, so each test can confirm normal
  /// extraction still happens rather than that the whole run produced nothing
  let source = """
    public protocol Labelable {
      func label() -> String
    }

    extension String: Labelable {
      public func label() -> String { self }
    }

    extension Int {
      public func doubled() -> Int { self * 2 }
    }

    public struct Widget: Labelable {
      public func label() -> String { "widget" }
    }
    """

  // ==== -----------------------------------------------------------------------
  // MARK: JNI

  @Test
  func jniEmitsNoJavaClassForForeignTypes() throws {
    var config = Configuration()
    config.enableJavaCallbacks = true

    try assertOutput(
      input: source,
      config: config,
      .jni,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        // The owned type still emits, and still implements the owned protocol
        """
        public final class Widget implements JNISwiftInstance, Labelable {
        """
      ],
      notExpectedChunks: [
        "class String",
        "class Int",
        // A member contributed to a foreign type must not surface either
        "doubled",
      ]
    )
  }

  @Test
  func jniEmitsNoThunksForForeignTypes() throws {
    var config = Configuration()
    config.enableJavaCallbacks = true

    try assertOutput(
      input: source,
      config: config,
      .jni,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("Java_com_example_swift_Widget__00024label__J")
        """
      ],
      notExpectedChunks: [
        "Java_com_example_swift_String_",
        "Java_com_example_swift_Int_",
        "doubled",
      ]
    )
  }

  // ==== -----------------------------------------------------------------------
  // MARK: FFM

  @Test
  func ffmEmitsNoJavaClassForForeignTypes() throws {
    try assertOutput(
      input: source,
      .ffm,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public final class Widget extends FFMSwiftInstance implements SwiftValue {
        """
      ],
      notExpectedChunks: [
        "class String",
        "class Int",
        "doubled",
      ]
    )
  }

  @Test
  func ffmEmitsNoThunksForForeignTypes() throws {
    try assertOutput(
      input: source,
      .ffm,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_Widget_label")
        """
      ],
      notExpectedChunks: [
        "swiftjava_SwiftModule_String_",
        "swiftjava_SwiftModule_Int_",
        "doubled",
      ]
    )
  }
}
