// Swift / Java native-image Interop Sample

import JEnvMap

@main
struct Main {
  static func main() {
    print("Graal native-image demo: libenvmap.dylib (Java native-image compiled library)")

    var isolate: OpaquePointer? = nil
    var thread: OpaquePointer? = nil

    guard graal_create_isolate(nil, &isolate, &thread) == 0 else {
      fatalError("Failed to initialize Graal isolate/thread")
    }

    print("Calling into JEnvMap...")
    let string = "JAVA"
    string.withCString {
      print("[swift] Number env variables with [\(string)] in the name:",
        filter_env(thread, UnsafeMutablePointer(mutating: $0)))
    }

    graal_tear_down_isolate(thread)
  }
}