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

import SwiftExtract

public typealias JavaFullyQualifiedTypeName = String

extension JavaTranslator {

  package struct SwiftToJavaMapping: Equatable {
    let swiftType: SwiftQualifiedTypeName
    let javaTypes: [JavaFullyQualifiedTypeName]

    package init(swiftType: SwiftQualifiedTypeName, javaTypes: [JavaFullyQualifiedTypeName]) {
      self.swiftType = swiftType
      self.javaTypes = javaTypes
    }
  }

  package enum ValidationError: Error, CustomStringConvertible {
    case multipleClassesMappedToSameName(swiftToJavaMapping: [SwiftToJavaMapping])

    package var description: String {
      switch self {
      case .multipleClassesMappedToSameName(let swiftToJavaMapping):
        """
        The following Java classes were mapped to the same Swift type name:
          \(swiftToJavaMapping.map(mappingDescription(mapping:)).joined(separator: "\n"))
        """
      }
    }

    private func mappingDescription(mapping: SwiftToJavaMapping) -> String {
      let javaTypes = mapping.javaTypes.map { "'\($0)'" }.joined(separator: ", ")
      return
        "Swift module: '\(mapping.swiftType.module ?? "")', type: '\(mapping.swiftType.fullName)', Java Types: \(javaTypes)"

    }
  }
  package func validateClassConfiguration() throws(ValidationError) {
    // Group all classes by swift name
    let groupedDictionary: [SwiftQualifiedTypeName: [(JavaFullyQualifiedTypeName, SwiftQualifiedTypeName)]] = Dictionary(
      grouping: translatedClasses,
      by: {
        $0.value
      }
    )
    // Find all that are mapped to multiple names
    let multipleClassesMappedToSameName: [SwiftQualifiedTypeName: [(JavaFullyQualifiedTypeName, SwiftQualifiedTypeName)]] =
      groupedDictionary.filter {
        (key: SwiftQualifiedTypeName, value: [(JavaFullyQualifiedTypeName, SwiftQualifiedTypeName)]) in
        value.count > 1
      }

    if !multipleClassesMappedToSameName.isEmpty {
      // Convert them to swift object and throw
      var errorMappings = [SwiftToJavaMapping]()
      for (swiftType, swiftJavaMappings) in multipleClassesMappedToSameName {
        errorMappings.append(SwiftToJavaMapping(swiftType: swiftType, javaTypes: swiftJavaMappings.map(\.0).sorted()))
      }
      throw ValidationError.multipleClassesMappedToSameName(swiftToJavaMapping: errorMappings)
    }

  }
}
