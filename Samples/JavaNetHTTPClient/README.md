# JavaNetHTTPClient — PoC

This sample implements the client-side protocol from
[`apple/swift-http-api-proposal`](https://github.com/apple/swift-http-api-proposal)
on top of `java.net.HttpURLConnection`, using `swift-java`'s JNI wrapper
generation.

## What it shows

- A `JavaNetHTTPClient` that conforms to `HTTPAPIs.HTTPClient`.
- The Java `HttpURLConnection` class wrapped via `swift-java.config` +
  `SwiftJavaPlugin` (build-time reflection-driven wrapper generation).
- Request bodies: the proposal's `HTTPClientRequestBody` is collected through
  a buffering `JavaNetWriter` and uploaded synchronously via
  `HttpURLConnection.getOutputStream()`. `Content-Length` is set when
  `knownLength` is known; otherwise chunked transfer encoding is enabled.
- A buffered, one-shot `AsyncReader` that hands the full response body in a
  single chunk — true streaming reads are left as future work.
- Distributed-tracing instrumentation: every `perform` call opens a
  `client`-kind span, the installed `Instrument` injects context (e.g. W3C
  `traceparent`) into the outgoing headers before they cross the
  detached-task boundary into the JNI call, and the response status is
  attached to the span as a standard semantic-convention attribute.

## What it does NOT show (deliberately)

- True streaming reads (response body comes back in one chunk).
- Streaming uploads (the request body is collected fully in memory before the
  JNI handoff).
- Trailers (HttpURLConnection doesn't surface them on HTTP/1.1).
- Redirects beyond `HttpURLConnection`'s default behaviour, retries,
  resumable uploads, TLS configuration.
- Android validation. The proposal's `Package.swift` lists Apple platforms
  only, which restricts the PoC to Apple hosts even though
  `HttpURLConnection` itself is Android-friendly.

## Running

This sample expects sibling checkouts of
`~/code/swift-java` and `~/code/swift-http-api-proposal`. From this directory:

```
xcrun swift build
DEMO_URL=https://www.example.com/ xcrun swift run JavaNetHTTPClientDemo

# POST a body
DEMO_URL=https://postman-echo.com/post \
DEMO_METHOD=POST \
DEMO_BODY='hello-from-swift-java-http' \
xcrun swift run JavaNetHTTPClientDemo
```

If `swift build` fails fetching `swift-java-jni-core`, set
`SWIFT_JAVA_JNI_CORE_PATH` to a local checkout:

```
SWIFT_JAVA_JNI_CORE_PATH=~/code/swift-java-jni-core xcrun swift build
```
