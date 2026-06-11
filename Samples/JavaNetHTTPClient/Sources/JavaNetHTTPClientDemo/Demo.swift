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

import BasicContainers
import Foundation
import HTTPAPIs
import JavaNetHTTPClient

@main
struct Demo {
  static func main() async throws {
    if #available(macOS 26.0, *) {
      let client = JavaNetHTTPClient()
      let env = ProcessInfo.processInfo.environment
      let target = env["DEMO_URL"] ?? "https://httpbin.org/get"
      guard let url = URL(string: target) else {
        print("Bad URL: \(target)")
        return
      }
      let methodName = env["DEMO_METHOD"] ?? "GET"
      let methodOpt = HTTPRequest.Method(methodName) ?? .get

      // Optional body driven by env vars: DEMO_BODY=<raw text>.
      let bodyData = env["DEMO_BODY"].map { Data($0.utf8) }
      var headers: HTTPFields = [:]
      if bodyData != nil {
        headers[.contentType] = "text/plain; charset=utf-8"
      }

      var request = HTTPRequest(method: methodOpt, url: url, headerFields: headers)
      _ = request

      let body: HTTPClientRequestBody<JavaNetWriter>? =
        bodyData.map { data in
          HTTPClientRequestBody<JavaNetWriter>.restartable(
            knownLength: Int64(data.count)
          ) { writer in
            var writer = writer
            var buffer = UniqueArray<UInt8>()
            buffer.reserveCapacity(data.count)
            for byte in data { buffer.append(byte) }
            try await writer.finish(buffer: &buffer, finalElement: nil)
          }
        }

      try await client.perform(request: request, body: body, options: .init()) { response, reader in
        print("status:", response.status.code)
        for field in response.headerFields {
          print("  \(field.name.canonicalName): \(field.value)")
        }
        var reader = reader
        try await reader.read { buffer, finalElement in
          var collected: [UInt8] = []
          collected.reserveCapacity(buffer.count)
          var index = buffer.startIndex
          while index != buffer.endIndex {
            collected.append(buffer[index])
            index = buffer.index(after: index)
          }
          if let s = String(bytes: collected, encoding: .utf8) {
            print("body (\(collected.count) bytes):\n\(s)")
          } else {
            print("body: <\(collected.count) bytes, non-utf8>")
          }
          if finalElement != nil { print("(final chunk)") }
          return ()
        }
      }
    } else {
      print("Requires macOS 26+")
    }
  }
}
