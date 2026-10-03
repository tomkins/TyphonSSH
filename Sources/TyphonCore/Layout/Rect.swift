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
