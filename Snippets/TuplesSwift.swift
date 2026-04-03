// snippet.tupleDefinition
public func returnPair() -> (Int64, String) {
  (42, "hello")
}

public func takePair(pair: (Int64, String)) -> String {
  "\(pair.0):\(pair.1)"
}

public func labeledTuple() -> (x: Int32, y: Int32) {
  (x: 10, y: 20)
}
// snippet.end
