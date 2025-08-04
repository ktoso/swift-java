//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftParser
import SwiftSyntax
import JavaKitConfigurationShared

final class Swift2JavaVisitor {
  let translator: Swift2JavaTranslator
  var config: Configuration {
    self.translator.config
  }

  init(translator: Swift2JavaTranslator) {
    self.translator = translator
  }

  var log: Logger { translator.log }

  func visit(sourceFile node: SourceFileSyntax) {
    for codeItem in node.statements {
      if let declNode = codeItem.item.as(DeclSyntax.self) {
        self.visit(decl: declNode, in: nil)
      }
    }
  }

  func visit(decl node: DeclSyntax, in parent: ImportedNominalType?) {
    log.trace("Visit this one: \(node.nameForDebug)")

    switch node.as(DeclSyntaxEnum.self) {
    case .actorDecl(let node):
      log.trace("Visit this actor: \(node.nameForDebug)")
      self.visit(nominalDecl: node, in: parent)
    case .classDecl(let node):
      log.trace("Visit this: class: \(node.nameForDebug)")
      self.visit(nominalDecl: node, in: parent)
    case .structDecl(let node):
      log.trace("Visit this: struct: \(node.nameForDebug)")
      self.visit(nominalDecl: node, in: parent)
    case .enumDecl(let node):
      log.trace("Visit this: enum: \(node.nameForDebug)")
      self.visit(nominalDecl: node, in: parent)
    case .protocolDecl(let node):
      log.trace("Visit this: protocol: \(node.nameForDebug)")
      self.visit(nominalDecl: node, in: parent)
    case .extensionDecl(let node):
      log.trace("Visit this: extension: \(node.nameForDebug)")
      self.visit(extensionDecl: node, in: parent)
    case .typeAliasDecl:
      break // TODO: Implement; https://github.com/swiftlang/swift-java/issues/338
    case .associatedTypeDecl:
      break // TODO: Implement

    case .initializerDecl(let node):
      self.visit(initializerDecl: node, in: parent)
    case .functionDecl(let node):
      self.visit(functionDecl: node, in: parent)
    case .variableDecl(let node):
      self.visit(variableDecl: node, in: parent)
    case .subscriptDecl:
      // TODO: Implement
      break

    default:
      break
    }
  }

  func visit(
    nominalDecl node: some DeclSyntaxProtocol & DeclGroupSyntax & NamedDeclSyntax & WithAttributesSyntax & WithModifiersSyntax,
    in parent: ImportedNominalType?
  ) {
    guard let importedNominalType = translator.importedNominalType(node, parent: parent) else {
      log.trace("Early return; Did not import: \(node)")
      return
    }
    for memberItem in node.memberBlock.members {
      self.visit(decl: memberItem.decl, in: importedNominalType)
    }
  }

  func visit(extensionDecl node: ExtensionDeclSyntax, in parent: ImportedNominalType?) {
    // guard parent != nil else {
    //   log.trace("'extension' in a nominal type is invalid. Ignore: \(node)")
    //   return
    // }
    guard let importedNominalType = translator.importedNominalType(node.extendedType) else {
      log.trace("Early return; Did not import: \(node)")
      return
    }
    for memberItem in node.memberBlock.members {
      self.visit(decl: memberItem.decl, in: importedNominalType)
    }

    log.trace("DONE visiting this one: \(node)")

    log.trace("members were = \(node.memberBlock.members)")
  }

  func visit(functionDecl node: FunctionDeclSyntax, in typeContext: ImportedNominalType?) {
    guard node.shouldExtract(config: config, log: log) else {
      return
    }

    self.log.debug("Import function: '\(node.qualifiedNameForDebug)'")

    let signature: SwiftFunctionSignature
    do {
      signature = try SwiftFunctionSignature(
        node,
        enclosingType: typeContext?.swiftType,
        lookupContext: translator.lookupContext
      )
    } catch {
      self.log.debug("Failed to import: '\(node.qualifiedNameForDebug)'; \(error)")
      return
    }

    let imported = ImportedFunc(
      module: translator.swiftModuleName,
      swiftDecl: node,
      name: node.name.text,
      apiKind: .function,
      functionSignature: signature
    )

    log.debug("Record imported method \(node.qualifiedNameForDebug)")
    if let typeContext {
      typeContext.methods.append(imported)
    } else {
      translator.importedGlobalFuncs.append(imported)
    }
  }

  func visit(variableDecl node: VariableDeclSyntax, in typeContext: ImportedNominalType?) {
    log.warning("Visit extension: \(node.nameForDebug)")
    guard node.shouldExtract(config: config, log: log) else {
      return
    }

    guard let binding = node.bindings.first else {
      return
    }

    let varName = "\(binding.pattern.trimmed)"

    self.log.debug("Import variable: \(node.kind) '\(node.qualifiedNameForDebug)'")

    func importAccessor(kind: SwiftAPIKind) throws {
      let signature = try SwiftFunctionSignature(
        node,
        isSet: kind == .setter,
        enclosingType: typeContext?.swiftType,
        lookupContext: translator.lookupContext
      )

      let imported = ImportedFunc(
        module: translator.swiftModuleName,
        swiftDecl: node,
        name: varName,
        apiKind: kind,
        functionSignature: signature
      )

      log.debug("Record imported variable accessor \(kind == .getter ? "getter" : "setter"):\(node.qualifiedNameForDebug)")
      if let typeContext {
        typeContext.variables.append(imported)
      } else {
        translator.importedGlobalVariables.append(imported)
      }
    }

    do {
      let supportedAccessors = node.supportedAccessorKinds(binding: binding)
      if supportedAccessors.contains(.get) {
        try importAccessor(kind: .getter)
      }
      if supportedAccessors.contains(.set) {
        try importAccessor(kind: .setter)
      }
    } catch {
      self.log.debug("Failed to import: \(node.qualifiedNameForDebug); \(error)")
    }
  }

  func visit(initializerDecl node: InitializerDeclSyntax, in typeContext: ImportedNominalType?) {
    guard let typeContext else {
      self.log.info("Initializer must be within a current type; \(node)")
      return
    }
    guard node.shouldExtract(config: config, log: log) else {
      return
    }

    self.log.debug("Import initializer: \(node.kind) '\(node.qualifiedNameForDebug)'")

    let signature: SwiftFunctionSignature
    do {
      signature = try SwiftFunctionSignature(
        node,
        enclosingType: typeContext.swiftType,
        lookupContext: translator.lookupContext
      )
    } catch {
      self.log.debug("Failed to import: \(node.qualifiedNameForDebug); \(error)")
      return
    }
    let imported = ImportedFunc(
      module: translator.swiftModuleName,
      swiftDecl: node,
      name: "init",
      apiKind: .initializer,
      functionSignature: signature
    )

    typeContext.initializers.append(imported)
  }
}

extension DeclSyntaxProtocol where Self: WithModifiersSyntax & WithAttributesSyntax {
  func shouldExtract(config: Configuration, log: Logger) -> Bool {
    let meetsRequiredAccessLevel: Bool =
      switch config.effectiveMinimumInputAccessLevelMode {
      case .public: self.isPublic
      case .package: self.isAtLeastPackage
      case .internal: self.isAtLeastInternal
      }

    guard meetsRequiredAccessLevel else {
      log.trace("Skip extracting '\(self.qualifiedNameForDebug)': not at least \(config.effectiveMinimumInputAccessLevelMode), node: \(self)")
      return false
    }
    guard !attributes.contains(where: { $0.isJava }) else {
      log.trace("Skip extracting '\(self.qualifiedNameForDebug)': is Java, node: \(self)")
      return false
    }

    if let node = self.as(InitializerDeclSyntax.self) {
      let isFailable = node.optionalMark != nil

      if isFailable {
        log.trace("Skip extracting '\(self.qualifiedNameForDebug)': failable initializer, node: \(self)")
        return false
      }
    }

    return true
  }
}
