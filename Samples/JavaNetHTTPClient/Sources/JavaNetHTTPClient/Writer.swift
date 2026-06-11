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

/// Buffering ``CallerAsyncWriter`` used by ``JavaNetHTTPClient`` to collect a
/// request body before the blocking JNI handoff.
///
/// The proposal hands the body's `produce` closure a fresh writer every time
/// the request runs; that closure calls `write(buffer:)` zero or more times
/// and ends with `finish(buffer:finalElement:)`. Because
/// `HttpURLConnection.getOutputStream()` is fully blocking and lives inside a
/// `Task.detached`, the writer concatenates everything into an in-memory
/// `[UInt8]` here. The collected bytes (and any trailer fields) are then
/// shipped across the detached-task boundary via
/// ``JavaNetHTTPClient/CollectedBody`` and replayed onto the Java
/// `OutputStream` synchronously.
///
/// Limitations:
/// - The whole body lives in memory at once; not suitable for very large or
///   unbounded uploads.
/// - Trailers cannot be sent over HTTP/1.1 by `HttpURLConnection`, so we
///   ignore the `finalElement` payload but still terminate cleanly.
@available(anyAppleOS 26.0, *)
public struct JavaNetWriter: CallerAsyncWriter, ~Copyable, SendableMetatype {
  public typealias WriteElement = UInt8
  public typealias WriteFailure = any Error
  public typealias FinalElement = HTTPFields?

  /// Reference-typed sink so the consuming `finish` can hand the bytes back
  /// without copying the whole buffer through value semantics yet again.
  internal final class Sink: @unchecked Sendable {
    var bytes: [UInt8] = []
    var trailer: HTTPFields??
    var finished: Bool = false
  }

  private let sink: Sink

  internal init(sink: Sink) {
    self.sink = sink
  }

  public mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
    buffer: inout Buffer
  ) async throws(any Error) where Buffer.Element: ~Copyable {
    if buffer.count == 0 { return }
    var consumer = buffer.consumeAll()
    var done = false
    while !done {
      let span = consumer.drainNext()
      if span.isEmpty {
        done = true
      } else {
        // Copy the span's contents into our accumulating array.
        span.span.withUnsafeBufferPointer { src in
          self.sink.bytes.append(contentsOf: src)
        }
      }
    }
  }

  public consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
    buffer: inout Buffer,
    finalElement: consuming HTTPFields?
  ) async throws(any Error) where Buffer.Element: ~Copyable {
    if buffer.count > 0 {
      try await self.write(buffer: &buffer)
    }
    self.sink.trailer = .some(finalElement)
    self.sink.finished = true
  }
}
