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

import JExtractSwiftLib
import Testing

@Suite
struct FFMArrayLoweringTests {

  // ==== -----------------------------------------------------------------------
  // MARK: [Int32] parameter

  @Test("Import: ([Int32]) -> Int32 (Java)")
  func int32ArrayParameter_java() throws {
    try assertOutput(
      input: "public func sumInts(_ ints: [Int32]) -> Int32 {}",
      .ffm,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        public static int sumInts(int[] ints) {
          try(var arena$ = Arena.ofConfined()) {
            return swiftjava_SwiftModule_sumInts__.call(arena$.allocateFrom(ValueLayout.JAVA_INT, ints), ints.length);
          }
        }
        """
      ]
    )
  }

  @Test("Import: ([Int32]) -> Int32 (Swift thunk)")
  func int32ArrayParameter_swift() throws {
    try assertOutput(
      input: "public func sumInts(_ ints: [Int32]) -> Int32 {}",
      .ffm,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_sumInts__")
        public func swiftjava_SwiftModule_sumInts__(_ ints_pointer: UnsafePointer<Int32>, _ ints_count: Int) -> Int32 {
          return sumInts([Int32](UnsafeBufferPointer<Int32>(start: ints_pointer, count: ints_count)))
        }
        """
      ]
    )
  }

  // ==== -----------------------------------------------------------------------
  // MARK: [Int32] return value

  @Test("Import: () -> [Int32] (Java)")
  func int32ArrayReturn_java() throws {
    try assertOutput(
      input: "public func makeInts(_ size: Int) -> [Int32] {}",
      .ffm,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static int[] makeInts(long size)",
        "int[] result = null",
        ".toArray(ValueLayout.JAVA_INT)",
      ]
    )
  }

  @Test("Import: () -> [Int32] (Swift thunk)")
  func int32ArrayReturn_swift() throws {
    try assertOutput(
      input: "public func makeInts(_ size: Int) -> [Int32] {}",
      .ffm,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        """
        @_cdecl("swiftjava_SwiftModule_makeInts__")
        public func swiftjava_SwiftModule_makeInts__(_ size: Int, _ _result_initialize: @convention(c) (UnsafePointer<Int32>, Int) -> ()) {
          let _result = makeInts(size)
          _result.withUnsafeBufferPointer({ (_0) in
            return _result_initialize(_0.baseAddress!, _0.count)
          })
        }
        """
      ]
    )
  }

  // ==== -----------------------------------------------------------------------
  // MARK: [Int16] parameter and return

  @Test("Import: ([Int16]) -> [Int16] (Java)")
  func int16ArrayRoundTrip_java() throws {
    try assertOutput(
      input: "public func roundTrip(_ s: [Int16]) -> [Int16] {}",
      .ffm,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static short[] roundTrip(short[] s)",
        "arena$.allocateFrom(ValueLayout.JAVA_SHORT, s)",
        "short[] result = null",
        ".toArray(ValueLayout.JAVA_SHORT)",
      ]
    )
  }

  @Test("Import: ([Int16]) -> [Int16] (Swift thunk)")
  func int16ArrayRoundTrip_swift() throws {
    try assertOutput(
      input: "public func roundTrip(_ s: [Int16]) -> [Int16] {}",
      .ffm,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "_ s_pointer: UnsafePointer<Int16>",
        "[Int16](UnsafeBufferPointer<Int16>(start: s_pointer, count: s_count))",
        "_result_initialize: @convention(c) (UnsafePointer<Int16>, Int) -> ()",
      ]
    )
  }

  // ==== -----------------------------------------------------------------------
  // MARK: [Int64] parameter and return

  @Test("Import: ([Int64]) -> [Int64] (Java)")
  func int64ArrayRoundTrip_java() throws {
    try assertOutput(
      input: "public func roundTrip(_ l: [Int64]) -> [Int64] {}",
      .ffm,
      .java,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "public static long[] roundTrip(long[] l)",
        "arena$.allocateFrom(ValueLayout.JAVA_LONG, l)",
        "long[] result = null",
        ".toArray(ValueLayout.JAVA_LONG)",
      ]
    )
  }

  @Test("Import: ([Int64]) -> [Int64] (Swift thunk)")
  func int64ArrayRoundTrip_swift() throws {
    try assertOutput(
      input: "public func roundTrip(_ l: [Int64]) -> [Int64] {}",
      .ffm,
      .swift,
      detectChunkByInitialLines: 1,
      expectedChunks: [
        "_ l_pointer: UnsafePointer<Int64>",
        "[Int64](UnsafeBufferPointer<Int64>(start: l_pointer, count: l_count))",
        "_result_initialize: @convention(c) (UnsafePointer<Int64>, Int) -> ()",
      ]
    )
  }
}
