import Logging

public func callMeSwifty() -> String {
  let logger = Logger(label: "com.example.swift.SampleLocalSwiftLibrary")
  logger.info("callMeSwifty() invoked from Java!")
  return "Hello from Swift!"
}

public class SwiftyGreeter {
  public var name: String

  public init(name: String) {
    self.name = name
  }

  public func greet() -> String {
    let logger = Logger(label: "com.example.swift.SampleLocalSwiftLibrary")
    logger.info("greet() called for \(name)")
    return "Hey \(name), welcome to Swift-Java interop!"
  }
}
