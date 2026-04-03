// snippet.enumDefinition
public enum Vehicle {
  case bicycle
  case car(String, trailer: String?)
  case motorbike(String, horsePower: Int64, helmets: Int32?)
  indirect case transformer(front: Vehicle, back: Vehicle)

  public init?(name: String) {
    switch name {
    case "bicycle": self = .bicycle
    default: return nil
    }
  }

  public var name: String {
    switch self {
    case .bicycle: "bicycle"
    case .car: "car"
    case .motorbike: "motorbike"
    case .transformer: "transformer"
    }
  }
}
// snippet.end
