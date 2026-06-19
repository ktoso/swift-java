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

/// A structured representation of a Swift qualified type name such as
/// `Logger.Message` (optionally with an owning module like `MyModule`).
///
/// Storage is split into three pieces so that callers don't have to re-parse
/// dotted strings:
/// - **module**: the owning Swift module, when known
/// - **qualified**: the qualifying parent components (outermost first), empty
///   for top-level types
/// - **name**: the leaf (innermost) name; always present
///
/// Self-documenting conversions to the various string forms used across the
/// codebase:
/// - **qualifiedName** (`Logger.Message`) - module-less, dot-joined, for Swift source
/// - **fullyQualifiedName** (`MyModule.Logger.Message`) - module + qualifiedName
/// - **fullFlatName** (`Logger_Message`) - underscore-joined for C symbols / Java identifiers
///
/// Java- or JNI-specific renderings (e.g. `Logger$Message` for JNI parent class
/// names) live as extensions in the Java-specific targets that consume them.
public struct SwiftQualifiedTypeName: Hashable, Sendable, CustomStringConvertible {
  /// Owning Swift module, if known.
  public let module: String?

  /// Qualifying parent components, outermost first. Empty for top-level types.
  /// Example: for `Outer.Inner.Leaf` this is `["Outer", "Inner"]`.
  public let qualified: [String]

  /// Leaf (innermost) name. Example: `"Leaf"` for `Outer.Inner.Leaf`.
  public let name: String

  public init(module: String? = nil, qualified: [String] = [], name: String) {
    self.module = module
    self.qualified = qualified
    self.name = name
  }

  /// Build from a non-empty list of components (parents + leaf).
  public init(_ components: [String], module: String? = nil) {
    precondition(!components.isEmpty)
    self.module = module
    self.qualified = Array(components.dropLast())
    self.name = components.last!
  }

  /// Build from a single leaf name (no parent components).
  public init(_ leafName: String, module: String? = nil) {
    self.module = module
    self.qualified = []
    self.name = leafName
  }

  /// Parse a dotted spelling like `"Outer.Inner.Leaf"` into its components.
  /// Use at boundaries (config files, command-line input) where the input is
  /// already a dotted string. Internal callers should prefer the explicit
  /// `init(module:qualified:name:)`.
  public init(parsing dottedName: String, module: String? = nil) {
    precondition(!dottedName.isEmpty)
    let parts = dottedName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    self.module = module
    self.qualified = Array(parts.dropLast())
    self.name = parts.last!
  }

  /// Build a name for a type nested directly inside this one.
  /// `Outer.Inner.makeChildType(named: "Leaf")` → `Outer.Inner.Leaf`.
  /// The child inherits this name's `module`.
  public func makeChildType(named childName: String) -> SwiftQualifiedTypeName {
    SwiftQualifiedTypeName(module: module, qualified: qualified + [name], name: childName)
  }

  // ==== ---------------------------------------------------------------------
  // MARK: Component views

  /// All name components from outermost to innermost (parents + leaf).
  public var components: [String] { qualified + [name] }

  /// Leaf name (innermost), e.g. `"Message"`. Same as `name`.
  public var leafName: String { name }

  /// `true` when this type is nested inside another type.
  public var isNested: Bool { !qualified.isEmpty }

  // ==== ---------------------------------------------------------------------
  // MARK: String renderings

  /// Dot-joined parents + leaf (no module), e.g. `"Logger.Message"`.
  public var fullName: String { components.joined(separator: ".") }

  /// Alias of `fullName` for callers that want to be explicit that the module
  /// is not included.
  public var qualifiedName: String { fullName }

  /// Module-prefixed dot-joined name, e.g. `"MyModule.Logger.Message"`.
  /// Falls back to `fullName` when no module is known.
  public var fullyQualifiedName: String {
    if let module {
      return "\(module).\(fullName)"
    }
    return fullName
  }

  /// Underscore-joined components for C symbols / Java identifiers,
  /// e.g. `"Logger_Message"`.
  public var fullFlatName: String { components.joined(separator: "_") }

  /// Like `fullName`, but each component except the first is wrapped in
  /// backticks if it's a Swift member-position keyword (e.g. `Type`).
  /// Used when interpolating a qualified type name into Swift source.
  public var qualifiedNameEscaped: String {
    var rendered = [String]()
    rendered.reserveCapacity(qualified.count + 1)
    for (offset, component) in components.enumerated() {
      if offset > 0 && Self.memberRequiresBackticks(component) {
        rendered.append("`\(component)`")
      } else {
        rendered.append(component)
      }
    }
    return rendered.joined(separator: ".")
  }

  /// CustomStringConvertible — uses `fullName` (no module) for stable diagnostics.
  public var description: String { fullName }

  /// True if `component`, used in member position (i.e. after a `.`), needs to
  /// be backtick-escaped to avoid clashing with a Swift contextual keyword.
  private static func memberRequiresBackticks(_ component: String) -> Bool {
    switch component {
    case "Type": return true
    default: return false
    }
  }
}
