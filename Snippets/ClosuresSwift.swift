// snippet.closureDefinition
public func emptyClosure(closure: () -> Void) {
  closure()
}

public func closureWithInt(input: Int64, closure: (Int64) -> Int64) -> Int64 {
  closure(input)
}

public func closureMultipleArguments(
  input1: Int64,
  input2: Int64,
  closure: (Int64, Int64) -> Int64
) -> Int64 {
  closure(input1, input2)
}
// snippet.end
