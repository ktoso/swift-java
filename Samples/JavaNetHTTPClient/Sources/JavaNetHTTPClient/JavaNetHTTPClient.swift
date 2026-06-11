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
import JavaIO
import JavaNet
import SwiftJava
import Tracing

/// PoC `HTTPClient` conformance backed by `java.net.HttpURLConnection`.
///
/// This sample demonstrates that the swift-http-api-proposal client surface
/// can be conformed to using a JNI-wrapped Java HTTP API. The implementation
/// is deliberately minimal: GET only, no request body, response collected
/// fully in memory, all JNI work funnelled through `Task.detached` because
/// `HttpURLConnection` is fully blocking.
///
/// Production-quality conformance would also implement:
/// - request bodies (write through `HttpURLConnection.getOutputStream()`)
/// - true streaming reads (one buffer chunk per `InputStream.read` call)
/// - retries / redirects / timeouts via `HTTPClientCapability` extensions
/// - a richer error mapping for `IOException` subclasses
@available(anyAppleOS 26.0, *)
public struct JavaNetHTTPClient: HTTPClient, Sendable {
  public typealias Writer = JavaNetWriter
  public typealias Reader = JavaNetReader
  public typealias RequestOptions = JavaNetRequestOptions

  public var defaultRequestOptions: JavaNetRequestOptions { .init() }

  public init() {}

  public func perform<Return: ~Copyable>(
    request: HTTPRequest,
    body: consuming HTTPClientRequestBody<JavaNetWriter>?,
    options: JavaNetRequestOptions,
    responseHandler: (HTTPResponse, consuming JavaNetReader) async throws -> Return
  ) async throws -> Return {
    guard let url = request.url else {
      throw JavaNetHTTPError.invalidRequestURL(
        "HTTPRequest could not be converted to a Foundation URL"
      )
    }

    // ==== -------------------------------------------------------------------
    // MARK: Tracing
    //
    // Open a client-kind span that covers the request execution. Header fields
    // are mutated in place so the installed Instrument can inject trace
    // context (W3C traceparent, baggage, ...) into them before they ferry
    // across the detached-task boundary.
    var outgoingHeaders = request.headerFields
    let span = InstrumentationSystem.tracer.startSpan(
      "HTTP \(request.method.rawValue)",
      ofKind: .client
    )
    defer { span.end() }

    InstrumentationSystem.instrument.inject(
      span.context,
      into: &outgoingHeaders,
      using: HTTPHeaderFieldsInjector()
    )

    // Standard HTTP-client span attributes (subset of OTel semantic conventions).
    span.attributes["http.request.method"] = request.method.rawValue
    span.attributes["url.full"] = url.absoluteString
    if let host = url.host { span.attributes["server.address"] = host }
    if let port = url.port { span.attributes["server.port"] = port }

    // ==== -------------------------------------------------------------------
    // MARK: Request body collection
    //
    // HttpURLConnection's getOutputStream() is fully blocking and lives inside
    // the detached task below, so we collect the entire body into memory here
    // first. The proposal's body model supports retries by replaying the body;
    // because this sample never retries, we drive `produce` exactly once.
    var collectedBody: CollectedBody? = nil
    if let body {
      let sink = JavaNetWriter.Sink()
      let writer = JavaNetWriter(sink: sink)
      do {
        try await body.produce(into: writer)
      } catch {
        span.recordError(error)
        throw JavaNetHTTPError.javaError(error)
      }
      collectedBody = CollectedBody(
        bytes: sink.bytes,
        knownLength: body.knownLength,
        trailer: sink.trailer ?? .none ?? nil
      )
    }

    let urlString = url.absoluteString
    let methodName = request.method.rawValue
    let headerPairs: [HeaderPair] = outgoingHeaders.map {
      HeaderPair(name: $0.name.canonicalName, value: $0.value)
    }

    let result: ExecutionResult
    do {
      result = try await Task.detached {
        try Self.executeBlocking(
          urlString: urlString,
          methodName: methodName,
          headerPairs: headerPairs,
          body: collectedBody
        )
      }.value
    } catch {
      span.recordError(error)
      throw error
    }

    span.attributes["http.response.status_code"] = Int(result.response.status.code)
    if result.response.status.kind == .clientError || result.response.status.kind == .serverError {
      span.setStatus(.init(code: .error))
    }

    var movableBuffer = UniqueArray<UInt8>()
    movableBuffer.reserveCapacity(result.bodyBytes.count)
    for byte in result.bodyBytes {
      movableBuffer.append(byte)
    }
    let reader = JavaNetReader(buffer: consume movableBuffer, trailer: nil)
    return try await responseHandler(result.response, consume reader)
  }

  // ==== ---------------------------------------------------------------------
  // MARK: Blocking JNI request execution

  /// Sendable, copyable carrier for header pairs across the detached-task
  /// boundary.
  fileprivate struct HeaderPair: Sendable {
    let name: String
    let value: String
  }

  /// Collected request body, plus its content-length hint and any trailer the
  /// caller emitted from `finish(buffer:finalElement:)`. Sendable + copyable
  /// so it can travel into a `Task.detached`.
  fileprivate struct CollectedBody: Sendable {
    let bytes: [UInt8]
    let knownLength: Int64?
    let trailer: HTTPFields?
  }

  /// Copyable result of the blocking JNI call. We avoid `~Copyable` types
  /// here so the value can travel through `Task.detached`.
  fileprivate struct ExecutionResult: Sendable {
    let response: HTTPResponse
    let bodyBytes: [UInt8]
  }

  /// Issues the HTTP request synchronously via `HttpURLConnection` and
  /// returns the parsed response together with the body bytes.
  private static func executeBlocking(
    urlString: String,
    methodName: String,
    headerPairs: [HeaderPair],
    body: CollectedBody?
  ) throws -> ExecutionResult {
    do {
      let javaURL = try JavaURL(urlString)
      let urlConnection = try javaURL.openConnection()
      guard let httpConnection = urlConnection?.as(HttpURLConnection.self) else {
        throw JavaNetHTTPError.unsupportedForPoC(
          "URL did not produce an HttpURLConnection (non-http(s) scheme?)."
        )
      }
      try httpConnection.setRequestMethod(methodName)
      httpConnection.setDoInput(true)
      httpConnection.setInstanceFollowRedirects(true)

      // Configure body sending. Only enable doOutput when we actually have a
      // body — turning it on forces the request method to POST for some Java
      // versions if no method override is specified, which we've already done
      // above.
      if let body {
        httpConnection.setDoOutput(true)
        if let knownLength = body.knownLength {
          // Prefer fixed-length streaming so HttpURLConnection sets a real
          // Content-Length header instead of buffering the body in memory.
          if knownLength <= Int64(Int32.max) {
            httpConnection.setFixedLengthStreamingMode(Int32(knownLength))
          } else {
            httpConnection.setFixedLengthStreamingMode(knownLength)
          }
        } else {
          // Unknown length → chunked transfer encoding.
          httpConnection.setChunkedStreamingMode(0)
        }
      }

      for pair in headerPairs {
        httpConnection.setRequestProperty(pair.name, pair.value)
      }

      try httpConnection.connect()

      // Send the request body, if any. Java's OutputStream.write takes a
      // signed [Int8], so reinterpret the unsigned bytes.
      if let body, !body.bytes.isEmpty {
        let outputStream = try httpConnection.getOutputStream()
        if outputStream == nil {
          throw JavaNetHTTPError.javaError(
            JavaNetHTTPError.unsupportedForPoC(
              "HttpURLConnection did not produce an OutputStream for body upload."
            )
          )
        }
        let signedBytes: [Int8] = body.bytes.map { Int8(bitPattern: $0) }
        try outputStream!.write(signedBytes)
        try outputStream!.flush()
        try outputStream!.close()
        // Trailers are not supported by HttpURLConnection's HTTP/1.1 client;
        // body.trailer is intentionally dropped after the body completes.
      }

      let statusCode = try httpConnection.getResponseCode()

      // HttpURLConnection routes the body to the error stream when
      // statusCode >= 400; fall back to it if the regular input stream throws.
      let stream: SwiftJava.InputStream? =
        ((try? httpConnection.getInputStream()) ?? httpConnection.getErrorStream())

      var bodyBytes: [UInt8] = []
      if let stream {
        // readAllBytes returns a Java byte[] which the wrapper exposes as [Int8];
        // bit-pattern-cast to UInt8 for the proposal's read element type.
        let signedBytes = try stream.readAllBytes()
        bodyBytes.reserveCapacity(signedBytes.count)
        for signedByte in signedBytes {
          bodyBytes.append(UInt8(bitPattern: signedByte))
        }
        try? stream.close()
      }
      httpConnection.disconnect()

      // Translate response headers. HttpURLConnection.getHeaderFields() returns
      // Map<String, List<String>> (with a null-keyed entry for the status line);
      // exposing that through swift-java is more involved than the PoC needs,
      // so we walk header indices instead.
      var responseFields = HTTPFields()
      var index: Int32 = 0
      while true {
        let key = httpConnection.getHeaderFieldKey(index)
        let value = httpConnection.getHeaderField(index)
        // The swift-java wrapper materialises Java nulls as "". The status-line
        // slot (index 0) has an empty key with a non-empty value, which we skip.
        let keyIsEmpty = key.isEmpty
        let valueIsEmpty = value.isEmpty
        if keyIsEmpty && valueIsEmpty {
          break
        }
        if !keyIsEmpty, !valueIsEmpty,
          let name = HTTPField.Name(key)
        {
          responseFields[name] = value
        }
        index += 1
      }

      let status = HTTPResponse.Status(code: Int(statusCode))
      let response = HTTPResponse(status: status, headerFields: responseFields)
      return ExecutionResult(response: response, bodyBytes: bodyBytes)
    } catch let error as JavaNetHTTPError {
      throw error
    } catch {
      throw JavaNetHTTPError.javaError(error)
    }
  }
}
