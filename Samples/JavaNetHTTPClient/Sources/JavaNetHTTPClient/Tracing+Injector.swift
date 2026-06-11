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

import HTTPAPIs
import Tracing

/// Injects ``ServiceContext`` values as HTTP request header fields.
///
/// Used by ``JavaNetHTTPClient`` to propagate distributed-tracing context
/// (W3C Trace Context, Baggage, etc.) through the outgoing request. Each
/// installed `Instrument` decides which keys it injects.
internal struct HTTPHeaderFieldsInjector: Injector {
  typealias Carrier = HTTPFields

  func inject(_ value: String, forKey key: String, into carrier: inout HTTPFields) {
    guard let name = HTTPField.Name(key) else {
      // The instrumentation handed us a non-RFC-9110 header name; skipping
      // is the closest we can do without crashing the request.
      return
    }
    carrier[name] = value
  }
}
