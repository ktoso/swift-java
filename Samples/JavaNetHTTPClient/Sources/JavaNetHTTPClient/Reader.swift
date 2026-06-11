//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncStreaming
import BasicContainers
import HTTPAPIs

/// PoC ``AsyncReader``. The full response body is collected into a single
/// `UniqueArray<UInt8>` while the request executes on a detached task; the
/// first `read(body:)` call yields that buffer along with the trailer (if any),
/// and any subsequent call yields an empty buffer with `finalElement == nil`
/// to indicate end-of-stream.
///
/// True streaming would require turning the JNI-managed `InputStream` into a
/// pull-based async source; deliberately out of scope for this sample.
@available(anyAppleOS 26.0, *)
public struct JavaNetReader: AsyncReader, ~Copyable, SendableMetatype {
  public typealias ReadElement = UInt8
  public typealias ReadFailure = any Error
  public typealias Buffer = UniqueArray<UInt8>
  public typealias FinalElement = HTTPFields?

  // None of these need to outlive the perform() invocation that owns the reader.
  private var pendingBuffer: UniqueArray<UInt8>?
  private var pendingTrailer: HTTPFields?
  private var done: Bool

  internal init(buffer: consuming UniqueArray<UInt8>, trailer: HTTPFields?) {
    self.pendingBuffer = consume buffer
    self.pendingTrailer = trailer
    self.done = false
  }

  public mutating func read<Return: ~Copyable, Failure: Error>(
    body: (inout UniqueArray<UInt8>, consuming HTTPFields??) async throws(Failure) -> Return
  ) async throws(EitherError<any Error, Failure>) -> Return {
    var buffer: UniqueArray<UInt8>
    var finalElement: HTTPFields?? = nil
    if !self.done {
      // First call: deliver the entire body and the trailer in one chunk.
      buffer = self.pendingBuffer.take() ?? UniqueArray()
      finalElement = .some(self.pendingTrailer)
      self.done = true
    } else {
      // Subsequent calls are a programmer error per the AsyncReader contract,
      // but to be defensive we hand back an empty terminal chunk.
      buffer = UniqueArray()
      finalElement = .some(nil)
    }

    let result: Return
    do {
      result = try await body(&buffer, finalElement)
    } catch {
      throw .second(error)
    }
    return result
  }
}
