// snippet.genericTypeDefinition
public struct MyID<T> {
  public var rawValue: T
  public init(_ rawValue: T) {
    self.rawValue = rawValue
  }
  public var description: String {
    "\(rawValue)"
  }
}
// snippet.end
