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

import SwiftSyntax

/// A single Swift attribute, such as @available or @SomeMacro.
struct SwiftAttribute {
  /// The attribute text, e.g. `@available(*, deprecated)`.
  var value: String

  /// The minimum Swift compiler version required to compile this attribute.
  /// When non-nil the attribute is wrapped in a `#if compiler(>=…)` block during rendering.
  var minimumCompilerVersion: SwiftVersion? = nil

  /// The originating SwiftSyntax node, when this attribute was created from
  /// parsed Swift source rather than synthesized from a Java annotation.
  var syntax: AttributeSyntax? = nil

  func render() -> String {
    self.value
  }
}

extension SwiftAttribute {
  public static var unavailable: SwiftAttribute {
    .init(value: "@available(unavailable, *)")
  }
}

struct SwiftAvailableAttributes {
  var attributes: [SwiftAttribute] = []

  func render() -> String {
    if attributes.isEmpty {
      return ""
    }
    var lines: [String] = []
    for attr in attributes {
      if let version = attr.minimumCompilerVersion {
        let versionString =
          version.patch.map { "\(version.major).\(version.minor).\($0)" }
          ?? "\(version.major).\(version.minor)"
        lines.append("#if compiler(>=\(versionString))")
        lines.append(attr.render())
        lines.append("#endif")
      } else {
        lines.append(attr.render())
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
