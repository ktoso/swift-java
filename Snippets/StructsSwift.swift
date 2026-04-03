// snippet.structDefinition
public struct MySwiftStruct {
  private var cap: Int64
  public var len: Int64

  public init(cap: Int64, len: Int64) {
    self.cap = cap
    self.len = len
  }

  public func getCapacity() -> Int64 { self.cap }

  public mutating func increaseCap(by value: Int64) -> Int64 {
    self.cap += value
    return self.cap
  }

  public subscript(index: Int64) -> Int64 {
    get { 0 }
    set {}
  }
}
// snippet.end
