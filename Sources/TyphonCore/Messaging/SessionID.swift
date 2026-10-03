/// Identifies one session window. Assigned by the controller, starting at 1,
/// in the order hosts were given.
public struct SessionID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
  public var rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public init(_ rawValue: Int) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension SessionID: CustomStringConvertible {
  public var description: String { String(rawValue) }
}
