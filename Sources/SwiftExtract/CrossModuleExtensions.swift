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

// ==== -----------------------------------------------------------------------
// MARK: Nominal identity

/// A module-qualified identity for a nominal type, usable as a dictionary key.
///
/// Neither existing identity in this module works for a type the analysis does not
/// declare. `SwiftNominalTypeDeclaration` has reference identity, and the built-in
/// module symbol tables are computed properties that rebuild their declarations on
/// each access, so two resolutions of `Swift.String` are two different objects.
/// `AnalysisResult.extractedTypes` is keyed by a module-*un*qualified name, so
/// `Swift.String` would collide with a `String` the analyzed module declares itself
public struct SwiftNominalIdentity: Hashable, Sendable, CustomStringConvertible {
  /// The module that declares this nominal, e.g. "Swift"
  public let moduleName: String

  /// The parent-chained name within that module, e.g. `GeneratedContent.Kind`
  public let typeName: SwiftQualifiedTypeName

  public init(moduleName: String, typeName: SwiftQualifiedTypeName) {
    self.moduleName = moduleName
    self.typeName = typeName
  }

  public init(_ decl: SwiftNominalTypeDeclaration) {
    self.moduleName = decl.moduleName
    self.typeName = decl.qualifiedTypeName
  }

  /// e.g. "Swift.String", "MyLib.GeneratedContent.Kind"
  public var fullyQualifiedName: String {
    "\(moduleName).\(typeName.fullName)"
  }

  /// Parent-chained but module-unqualified: the spelling `extractedTypes` is keyed by
  public var qualifiedName: String {
    typeName.fullName
  }

  public var leafName: String {
    typeName.leafName
  }

  public var description: String { fullyQualifiedName }
}

// ==== -----------------------------------------------------------------------
// MARK: Contributed members

/// The members a single extension contributes to the type it extends
public struct CrossModuleExtensionMembers {
  public var initializers: [ExtractedFunc]
  public var methods: [ExtractedFunc]
  public var variables: [ExtractedFunc]

  public init(
    initializers: [ExtractedFunc] = [],
    methods: [ExtractedFunc] = [],
    variables: [ExtractedFunc] = []
  ) {
    self.initializers = initializers
    self.methods = methods
    self.variables = variables
  }

  public var isEmpty: Bool {
    initializers.isEmpty && methods.isEmpty && variables.isEmpty
  }
}

// ==== -----------------------------------------------------------------------
// MARK: A cross-module extension

/// One `extension` the analyzed sources declare on a nominal type from another module
public struct CrossModuleExtension {
  /// The foreign nominal being extended
  public let extendedType: SwiftNominalIdentity

  /// The extension declaration as written
  public let syntax: ExtensionDeclSyntax

  /// Protocols this extension adds, resolved. Empty for a members-only extension
  public let addedConformances: [SwiftType]

  /// Members this extension contributes
  public let members: CrossModuleExtensionMembers

  /// `where` requirements, resolved. Empty for an unconditional extension
  public let requirements: [SwiftGenericRequirement]

  /// True when the `where` clause held a requirement this analyzer cannot represent
  /// (a layout requirement, or one whose types did not resolve).
  ///
  /// Load-bearing rather than informational: without it, an extension whose only
  /// requirement was unrepresentable would present as unconditional, and a consumer
  /// would grant the conformance unconditionally. `isConditional` accounts for it
  public let hasUnrepresentableRequirements: Bool

  /// The extension's own attributes, `@available` among them. Preserved because a
  /// consumer that later emits these members must reproduce their availability
  public let attributes: AttributeListSyntax

  public let sourceFilePath: String

  public init(
    extendedType: SwiftNominalIdentity,
    syntax: ExtensionDeclSyntax,
    addedConformances: [SwiftType],
    members: CrossModuleExtensionMembers,
    requirements: [SwiftGenericRequirement],
    hasUnrepresentableRequirements: Bool = false,
    attributes: AttributeListSyntax,
    sourceFilePath: String
  ) {
    self.extendedType = extendedType
    self.syntax = syntax
    self.addedConformances = addedConformances
    self.members = members
    self.requirements = requirements
    self.hasUnrepresentableRequirements = hasUnrepresentableRequirements
    self.attributes = attributes
    self.sourceFilePath = sourceFilePath
  }

  /// Whether the conformances this extension adds apply only under its `where` clause
  public var isConditional: Bool {
    !requirements.isEmpty || hasUnrepresentableRequirements
  }
}

/// An extension whose extended type could not be resolved at all.
///
/// A diagnostics channel rather than a worklist. These were previously discarded with
/// no trace, which made an unresolvable import indistinguishable from an empty extension
public struct UnresolvedExtension {
  /// The extended type as written, e.g. "SomeUnknownModule.Widget"
  public let extendedTypeDescription: String
  public let syntax: ExtensionDeclSyntax
  public let sourceFilePath: String

  public init(extendedTypeDescription: String, syntax: ExtensionDeclSyntax, sourceFilePath: String) {
    self.extendedTypeDescription = extendedTypeDescription
    self.syntax = syntax
    self.sourceFilePath = sourceFilePath
  }
}

// ==== -----------------------------------------------------------------------
// MARK: The collection

/// The cross-module extensions found by one analysis.
///
/// A module cannot declare a nominal type owned by another module, so an extension is
/// the only way the analyzed sources can add conformances or members to a foreign type.
/// This is therefore the complete record of what the analysis learned about types it
/// does not declare.
///
/// Separate from `AnalysisResult.extractedTypes`, which is the set of types a generator
/// should emit bindings for. A type appearing here carries no implication that it should
/// be emitted, and generators that iterate `extractedTypes` are unaffected by anything
/// recorded here
public struct CrossModuleExtensions {
  /// Every recorded cross-module extension, in the order encountered
  public private(set) var all: [CrossModuleExtension] = []

  /// Extensions whose extended type never resolved
  public private(set) var unresolved: [UnresolvedExtension] = []

  /// Index into `all`, keyed by extended type
  private var byExtendedType: [SwiftNominalIdentity: [Int]] = [:]

  public init() {}

  public var isEmpty: Bool {
    all.isEmpty && unresolved.isEmpty
  }

  public mutating func record(_ extension: CrossModuleExtension) {
    byExtendedType[`extension`.extendedType, default: []].append(all.count)
    all.append(`extension`)
  }

  public mutating func record(unresolved unresolvedExtension: UnresolvedExtension) {
    unresolved.append(unresolvedExtension)
  }

  /// Every cross-module extension on `type`, in the order encountered
  public func extensions(of type: SwiftNominalIdentity) -> [CrossModuleExtension] {
    (byExtendedType[type] ?? []).map { all[$0] }
  }

  /// Every foreign nominal that some cross-module extension extends, in a stable order
  public var extendedTypes: [SwiftNominalIdentity] {
    var seen: Set<SwiftNominalIdentity> = []
    var ordered: [SwiftNominalIdentity] = []
    for record in all where seen.insert(record.extendedType).inserted {
      ordered.append(record.extendedType)
    }
    return ordered
  }
}
