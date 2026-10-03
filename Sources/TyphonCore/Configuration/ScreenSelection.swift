/// Which display(s) to tile windows on. Screens are numbered from 1.
///
/// A span such as `1-2` uses a rectangle reaching across both displays.
public enum ScreenSelection: Hashable, Sendable {
  case single(Int)
  case span(Int, Int)

  public static let main = ScreenSelection.single(1)

  public var screens: [Int] {
    switch self {
    case .single(let screen): [screen]
    case .span(let first, let second): [first, second]
    }
  }
}

extension ScreenSelection: LosslessStringConvertible {
  public init?(_ description: String) {
    let parts = description.split(separator: "-", omittingEmptySubsequences: false)
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 1 }) else { return nil }
    switch numbers.count {
    case 1: self = .single(numbers[0])
    case 2: self = .span(numbers[0], numbers[1])
    default: return nil
    }
  }

  public var description: String {
    screens.map(String.init).joined(separator: "-")
  }
}

extension ScreenSelection: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self), let screen = ScreenSelection(String(number)) {
      self = screen
    } else if let string = try? container.decode(String.self), let screen = ScreenSelection(string)
    {
      self = screen
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Screen must be a number (e.g. 1) or a range (e.g. \"1-2\")"
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .single(let screen): try container.encode(screen)
    case .span: try container.encode(description)
    }
  }
}
