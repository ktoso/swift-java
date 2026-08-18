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

import SwiftSyntax

public struct SwiftFunctionType: Equatable {
  public enum Convention: Equatable {
    case swift
    case c
  }

  public var convention: Convention
  public var parameters: [SwiftParameter]
  public var resultType: SwiftType
  public var isEscaping: Bool = false

  public var effectSpecifiers: [SwiftEffectSpecifier] = []

  public var isAsync: Bool { effectSpecifiers.contains(.async) }
  public var isThrowing: Bool { effectSpecifiers.contains(.throws) }

  public init(
    convention: Convention,
    parameters: [SwiftParameter],
    resultType: SwiftType,
    isEscaping: Bool = false,
    effectSpecifiers: [SwiftEffectSpecifier] = []
  ) {
    self.convention = convention
    self.parameters = parameters
    self.resultType = resultType
    self.isEscaping = isEscaping
    self.effectSpecifiers = effectSpecifiers
  }
}

extension SwiftFunctionType: CustomStringConvertible {
  public var description: String {
    let parameterString = parameters.map { $0.descriptionInType }.joined(separator: ", ")
    let conventionPrefix =
      switch convention {
      case .c: "@convention(c) "
      case .swift: ""
      }
    let escapingPrefix = isEscaping ? "@escaping " : ""
    let effectsSuffix =
      (isAsync ? " async" : "")
      + (isThrowing ? " throws" : "")
    return "\(escapingPrefix)\(conventionPrefix)(\(parameterString))\(effectsSuffix) -> \(resultType.description)"
  }
}

extension SwiftFunctionType {
  public init(
    _ node: FunctionTypeSyntax,
    convention: Convention,
    isEscaping: Bool = false,
    lookupContext: SwiftTypeLookupContext
  ) throws {
    self.convention = convention
    self.isEscaping = isEscaping
    self.parameters = try node.parameters.map { param in
      let isInout = param.inoutKeyword != nil
      return SwiftParameter(
        convention: isInout ? .inout : .byValue,
        type: try SwiftType(param.type, lookupContext: lookupContext)
      )
    }

    self.resultType = try SwiftType(node.returnClause.type, lookupContext: lookupContext)

    var effectSpecifiers: [SwiftEffectSpecifier] = []
    if node.effectSpecifiers?.asyncSpecifier != nil {
      effectSpecifiers.append(.async)
    }
    if node.effectSpecifiers?.throwsClause != nil {
      effectSpecifiers.append(.throws)
    }
    self.effectSpecifiers = effectSpecifiers
  }
}
