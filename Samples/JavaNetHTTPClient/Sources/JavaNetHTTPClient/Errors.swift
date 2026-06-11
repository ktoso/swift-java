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

/// Errors emitted by ``JavaNetHTTPClient`` and its supporting types.
public enum JavaNetHTTPError: Error, Sendable {
  /// The underlying Java HTTP call failed; the wrapped throwable is the
  /// translated Java exception (typically `IOException`).
  case javaError(any Error)

  /// The PoC only supports a subset of the proposal surface. Anything that
  /// requires features the PoC has not implemented yet (e.g. request bodies,
  /// non-GET verbs, true streaming) throws this.
  case unsupportedForPoC(String)

  /// The request could not be turned into a `java.net.URI`.
  case invalidRequestURL(String)
}
