// snippet.classDefinition
public class MySwiftClass {
  public let x: Int64
  public let y: Int64

  public var mutable: Int64 = 0
  public var product: Int64 { x * y }

  public init(x: Int64, y: Int64) {
    self.x = x
    self.y = y
  }

  convenience public init(throwing: Bool) throws {
    self.init(x: 0, y: 0)
  }

  public func sum() -> Int64 { x + y }
  public func xMultiplied(by z: Int64) -> Int64 { x * z }
  public func throwingFunction() throws {}
}
// snippet.end
