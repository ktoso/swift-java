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

extension SwiftQualifiedTypeName {
  /// Build a qualified type name from a `TypeSyntax` chain.
  ///
  /// Walks `MemberTypeSyntax` / `IdentifierTypeSyntax` and collects the
  /// type-name components from outermost to innermost - `Logger.Message`
  /// produces `["Logger", "Message"]`.
  ///
  /// SE-0491 module selectors (`Module::Type`) are recognised: a leading
  /// `moduleSelector` is treated as the module disambiguator, NOT as a
  /// type-name component, so `Module::Logger.Message` produces
  /// `["Logger", "Message"]`.
  ///
  /// If `moduleName` is supplied, a leading bare-identifier component that
  /// matches it is also stripped - `Module.Logger.Message` (legacy dot
  /// form) produces `["Logger", "Message"]`.
  ///
  /// Returns `nil` for unsupported root forms (function, tuple, existential,
  /// etc.) or when no type-name component remains after stripping.
  public init?(_ typeSyntax: TypeSyntax, moduleName: String? = nil) {
    var components: [String] = []
    var current: TypeSyntax = typeSyntax

    walk: while true {
      if let member = current.as(MemberTypeSyntax.self) {
        components.insert(member.name.text, at: 0)
        current = member.baseType
      } else if let ident = current.as(IdentifierTypeSyntax.self) {
        components.insert(ident.name.text, at: 0)
        if ident.moduleSelector != nil {
          // Leading `Module::Type` - module is explicit; the type-name
          // path is everything we have collected so far. The module
          // identifier itself is NOT part of the components.
          break walk
        }
        break walk
      } else {
        return nil
      }
    }

    if let moduleName, components.first == moduleName {
      components.removeFirst()
    }

    guard !components.isEmpty else { return nil }
    self.init(components)
  }
}
