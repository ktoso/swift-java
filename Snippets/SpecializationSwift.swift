// snippet.boxSpecialization
public struct Box<Element> {
  public var count: Int64
  public init(count: Int64) { self.count = count }
}

public struct Fish {
  public var name: String
  public init(name: String) { self.name = name }
}

extension Box where Element == Fish {
  public func describeFish() -> String {
    "A box of \(count) fish"
  }
}

public typealias FishBox = Box<Fish>
// snippet.end
