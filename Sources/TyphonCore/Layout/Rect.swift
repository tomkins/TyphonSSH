/// A rectangle in screen coordinates with the origin at the top-left of the
/// main display and y increasing downwards, matching AppleScript window bounds.
public struct Rect: Hashable, Codable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var maxX: Double { x + width }
  public var maxY: Double { y + height }
}

extension Rect: CustomStringConvertible {
  public var description: String {
    "{x: \(Int(x)), y: \(Int(y)), width: \(Int(width)), height: \(Int(height))}"
  }
}

extension Rect {
  /// A rectangle reaching across two displays.
  ///
  /// On each axis, if the displays sit side by side the result spans both;
  /// if they overlap on that axis, the result is limited to the overlap so
  /// windows aren't placed off-screen. Odd arrangements (such as an L shape)
  /// may still include area that neither display covers.
  public static func spanning(_ first: Rect, _ second: Rect) -> Rect {
    func span(
      _ firstStart: Double, _ firstLength: Double, _ secondStart: Double, _ secondLength: Double
    ) -> (Double, Double) {
      if secondStart >= firstStart + firstLength {
        (firstStart, secondStart + secondLength - firstStart)
      } else if firstStart >= secondStart + secondLength {
        (secondStart, firstStart + firstLength - secondStart)
      } else {
        (max(firstStart, secondStart), min(firstLength, secondLength))
      }
    }
    let (x, width) = span(first.x, first.width, second.x, second.width)
    let (y, height) = span(first.y, first.height, second.y, second.height)
    return Rect(x: x, y: y, width: width, height: height)
  }

  /// Moves the rectangle by `dx`, `dy`.
  public func offsetBy(dx: Double, dy: Double) -> Rect {
    Rect(x: x + dx, y: y + dy, width: width, height: height)
  }

  /// Grows (or with negative values, shrinks) the rectangle from its top-left corner.
  public func resizedBy(dWidth: Double, dHeight: Double) -> Rect {
    Rect(x: x, y: y, width: max(1, width + dWidth), height: max(1, height + dHeight))
  }
}
