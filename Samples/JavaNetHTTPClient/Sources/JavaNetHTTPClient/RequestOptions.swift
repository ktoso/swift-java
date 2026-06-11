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

/// PoC request options. The proposal allows clients to advertise extra
/// capabilities through child protocols of ``HTTPClientCapability/RequestOptions``;
/// this sample currently advertises none.
@available(anyAppleOS 26.0, *)
public struct JavaNetRequestOptions: HTTPClientCapability.RequestOptions, Sendable {
  public init() {}
}
