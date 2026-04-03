// snippet.throwingInitDefinition
public class ThrowingInitExample {
  public let value: Int64

  public init(value: Int64) {
    self.value = value
  }

  // Throwing initializer
  convenience public init(throwing: Bool) throws {
    self.init(value: 0)
  }

  // Optional (failable) initializer
  public init?(name: String) {
    guard name != "invalid" else { return nil }
    self.value = 0
  }
}
// snippet.end
