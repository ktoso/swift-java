// snippet.escapingClosureDefinition
public class CallbackManager {
  private var callback: (() -> Void)?

  public init() {}

  public func setCallback(callback: @escaping () -> Void) {
    self.callback = callback
  }

  public func triggerCallback() {
    callback?()
  }

  public func clearCallback() {
    callback = nil
  }
}
// snippet.end
