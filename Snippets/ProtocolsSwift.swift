// snippet.protocolDefinition
public protocol ProtocolA {
  var constantA: Int64 { get }
  var mutable: Int64 { get set }
  func name() -> String
}
// snippet.end

// snippet.protocolUsage
public protocol ProtocolB {
  var constantB: Int64 { get }
}

public func takeProtocol(_ proto1: any ProtocolA, _ proto2: some ProtocolA) -> Int64 {
  proto1.constantA + proto2.constantA
}

public func takeCombinedProtocol(_ proto: some ProtocolA & ProtocolB) -> Int64 {
  proto.constantA + proto.constantB
}
// snippet.end
