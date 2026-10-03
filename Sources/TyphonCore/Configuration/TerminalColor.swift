/// An RGB colour with 16-bit components, the precision Terminal.app's scripting interface uses.
///
/// Written in configuration as either web-style hex (`"#4689D0"`, `"4689D0"`)
/// or AppleScript-style 16-bit triples (`"{17990,35209,53456}"`).
public struct TerminalColor: Hashable, Sendable {
  public var red: UInt16
  public var green: UInt16
  public var blue: UInt16

  public init(red: UInt16, green: UInt16, blue: UInt16) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init?(_ string: String) {
    let text = string.filter { !$0.isWhitespace }
    if text.hasPrefix("{"), text.hasSuffix("}") {
      let components = text.dropFirst().dropLast().split(
        separator: ",", omittingEmptySubsequences: false)
      guard components.count == 3 else { return nil }
      let values = components.compactMap { UInt16($0) }
      guard values.count == 3 else { return nil }
      self.init(red: values[0], green: values[1], blue: values[2])
    } else {
      let hex = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
      guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
      // Scale 8-bit to 16-bit so that FF maps to 65535.
      self.init(
        red: UInt16(value >> 16 & 0xFF) * 257,
        green: UInt16(value >> 8 & 0xFF) * 257,
        blue: UInt16(value & 0xFF) * 257
      )
    }
  }

  /// The colour as an AppleScript list, e.g. `{17990, 35209, 53456}`.
  public var appleScriptLiteral: String {
    "{\(red), \(green), \(blue)}"
  }

  public static let white = TerminalColor(red: 65535, green: 65535, blue: 65535)
}

extension TerminalColor: CustomStringConvertible {
  public var description: String { "{\(red),\(green),\(blue)}" }
}

extension TerminalColor: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let color = TerminalColor(string) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription:
          "Invalid colour \"\(string)\"; use \"#RRGGBB\" or \"{r,g,b}\" with 16-bit components"
      )
    }
    self = color
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

/// A foreground/background pair. Either side may be absent, meaning "leave as is".
public struct ColorPair: Hashable, Codable, Sendable {
  public var foreground: TerminalColor?
  public var background: TerminalColor?

  public init(foreground: TerminalColor? = nil, background: TerminalColor? = nil) {
    self.foreground = foreground
    self.background = background
  }
}
