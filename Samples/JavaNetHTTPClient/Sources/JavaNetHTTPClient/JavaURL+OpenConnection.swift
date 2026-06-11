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

import JavaNet
import SwiftJava
import SwiftJavaJNICore

/// Manually-bridged JNI methods that swift-java's `wrap-java` reflection scan
/// does not currently include in the auto-generated `JavaURL` wrapper.
extension JavaURL {
  /// java.net.URL#openConnection().
  ///
  /// ### Java method signature
  /// ```java
  /// public java.net.URLConnection openConnection() throws java.io.IOException
  /// ```
  @JavaMethod
  func openConnection() throws -> URLConnection!
}
