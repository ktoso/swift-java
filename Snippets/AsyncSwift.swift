// snippet.asyncDefinition
public func asyncSum(i1: Int64, i2: Int64) async -> Int64 {
  i1 + i2
}

public func asyncSleep() async throws {
  try await Task.sleep(for: .milliseconds(500))
}

public func asyncString(input: String) async -> String {
  input
}
// snippet.end
