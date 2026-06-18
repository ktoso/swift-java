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

import JavaLangReflect
import SwiftJava

extension JavaClassTranslator {
  private func apiLevelComment(_ level: Int32) -> String {
    AndroidAPILevel(rawValue: Int(level)).map { " /* \($0.name) */" } ?? ""
  }

  private func availabilityFromBinRequiresApi(_ binAnnotation: JavaRuntimeInvisibleAnnotation) -> SwiftAttribute? {
    let apiLevel: Int32? =
      if let api = binAnnotation.elements["api"], api > 0 {
        api
      } else if let value = binAnnotation.elements["value"], value > 0 {
        value
      } else {
        nil
      }

    guard let apiLevel else { return nil }
    return SwiftAttribute(
      value: "@available(Android \(apiLevel)\(apiLevelComment(apiLevel)), *)",
      minimumCompilerVersion: .androidPlatformAvailability
    )
  }

  /// Build Swift `@available` attributes from Java annotations on a reflective element.
  func swiftAvailableAttributes(
    from runtimeAnnotations: [Annotation],
    runtimeInvisibleAnnotations: [JavaRuntimeInvisibleAnnotation] = [],
    javaClass: JavaClass<JavaObject>? = nil,
    javaMethod: Method? = nil,
    javaConstructor: Executable? = nil,
    javaFieldName: String? = nil
  ) -> SwiftAvailableAttributes {
    var attributes: [SwiftAttribute] = []

    for annotation in runtimeAnnotations {
      guard let annotationClass = annotation.annotationType() else { continue }

      if annotationClass.isKnown(.javaLangDeprecated) {
        attributes += [SwiftAttribute(value: "@available(*, deprecated)")]
      }
    }

    // Look for any annotations stored in classfiles, e.g. the Android @
    for binAnnotation in runtimeInvisibleAnnotations {
      let fqn = binAnnotation.fullyQualifiedName

      // Handle Android's RequiresApi; though they don't exist in android.jar (!)
      if fqn == KnownJavaAnnotation.androidxRequiresApi.rawValue
        || fqn == KnownJavaAnnotation.androidSupportRequiresApi.rawValue
      {
        if let attr = availabilityFromBinRequiresApi(binAnnotation) {
          attributes += [attr]
        }
      }
    }

    // For android, the RequiresApi actually are synthetic and stored in api-versions.xml,
    // so consult that if available
    if let apiVersions = translator.androidAPIVersions, let javaClass {
      let className = javaClass.getName()
      let versionInfo: AndroidAPIAvailability? =
        if let javaMethod {
          apiVersions.versionInfo(forClass: className, methodDescriptor: jvmMethodDescriptor(javaMethod))
        } else if let javaConstructor {
          apiVersions.versionInfo(forClass: className, methodDescriptor: jvmMethodDescriptor(javaConstructor))
        } else if let fieldName = javaFieldName {
          apiVersions.versionInfo(forClass: className, fieldName: fieldName)
        } else {
          apiVersions.versionInfo(forClass: className)
        }

      if let info = versionInfo {
        let alreadyHasAndroidAvailable = attributes.contains {
          $0.value.contains("@available(Android")
        }

        // Only add since from api-versions.xml if @RequiresApi didn't already provide one.
        if !alreadyHasAndroidAvailable, let since = info.since, since.rawValue > 0 {
          attributes += [
            SwiftAttribute(
              value: "@available(Android \(since.rawValue) /* \(since.name) */, *)",
              minimumCompilerVersion: .androidPlatformAvailability
            )
          ]
        }

        let alreadyHasDeprecated = attributes.contains {
          $0.value.contains("deprecated")
        }

        // Handle deprecated APIs; also emit deprecated for removed APIs if not already deprecated.
        if !alreadyHasDeprecated, let deprecated = info.deprecated {
          attributes += [
            SwiftAttribute(
              value: "@available(Android, deprecated: \(deprecated.rawValue), message: \"Deprecated in Android API \(deprecated.rawValue) /* \(deprecated.name) */\")",
              minimumCompilerVersion: .androidPlatformAvailability
            )
          ]
        } else if !alreadyHasDeprecated, let removed = info.removed {
          // Swift's '@available(Android, unavailable, ...' does not accept a version so we don't use it,
          // since it may prevent calling an API that's actually still there in some Android version we're targeting.
          attributes += [
            SwiftAttribute(
              value: "@available(Android, deprecated: \(removed.rawValue), message: \"Removed in Android API \(removed.rawValue) /* \(removed.name) */\")",
              minimumCompilerVersion: .androidPlatformAvailability
            )
          ]
        }
      }
    }

    return SwiftAvailableAttributes(attributes: attributes)
  }
}
