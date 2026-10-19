/// Which display(s) to tile windows on. Screens are numbered from 1.
///
/// Each selected screen is tiled separately, so no window straddles two
/// displays. The windows are shared between the screens in proportion to their
/// size, and the controller runs along the bottom of the first.
public enum ScreenSelection: Hashable, Sendable {
  /// The listed screens, in order.
  case screens([Int])
  /// Every screen, in order.
  case all

  public static let main = ScreenSelection.single(1)

  public static func single(_ screen: Int) -> ScreenSelection { .screens([screen]) }
}

extension ScreenSelection: LosslessStringConvertible {
  /// Reads `all`, a screen number such as `2`, a range such as `1-3` (or `3-1`
  /// to reverse the order), or a comma-separated list of those, such as `2,1`.
  public init?(_ description: String) {
    if description == "all" {
      self = .all
      return
    }
    var screens: [Int] = []
    for item in description.split(separator: ",", omittingEmptySubsequences: false) {
      let ends = item.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
      guard let first = ends.first, let last = ends.last, ends.count <= 2,
        let first, let last, first >= 1, last >= 1
      else { return nil }
      screens += first <= last ? Array(first...last) : Array((last...first).reversed())
    }
    guard Set(screens).count == screens.count else { return nil }
    self = .screens(screens)
  }

  public var description: String {
    switch self {
    case .screens(let screens): screens.map(String.init).joined(separator: ",")
    case .all: "all"
    }
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
        debugDescription:
          #"Screen must be a number (e.g. 1), a range (e.g. "1-2"), a list (e.g. "1,3") or "all""#
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .screens(let screens) where screens.count == 1: try container.encode(screens[0])
    default: try container.encode(description)
    }
  }
}
