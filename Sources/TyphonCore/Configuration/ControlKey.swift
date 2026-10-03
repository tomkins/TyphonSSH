/// A control-key chord such as Ctrl-A, used to enter the controller's action menu.
///
/// Written in configuration as `"ctrl-a"` or `"^A"`.
public struct ControlKey: Hashable, Sendable {
  /// The byte the terminal sends for this chord, e.g. `0x01` for Ctrl-A.
  public let byte: UInt8

  public init?(byte: UInt8) {
    guard (0x01...0x1F).contains(byte), byte != 0x1B else { return nil }
    self.byte = byte
  }

  public init?(_ string: String) {
    let lowered = string.lowercased()
    let key: Substring
    if lowered.hasPrefix("ctrl-") {
      key = lowered.dropFirst(5)
    } else if lowered.hasPrefix("^") {
      key = lowered.dropFirst()
    } else {
      return nil
    }
    guard key.count == 1, let ascii = key.uppercased().first?.asciiValue,
      (0x41...0x5F).contains(ascii)
    else {
      return nil
    }
    self.init(byte: ascii - 0x40)
  }

  public static let ctrlA = ControlKey(byte: 0x01)!

  /// The letter or symbol on the key, e.g. `A` for Ctrl-A.
  public var keyName: String { String(UnicodeScalar(byte + 0x40)) }
}

extension ControlKey: CustomStringConvertible {
  /// Human-readable form, e.g. `Ctrl-A`.
  public var description: String { "Ctrl-\(keyName)" }
}

extension ControlKey: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    guard let key = ControlKey(string) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid action key \"\(string)\"; use e.g. \"ctrl-a\""
      )
    }
    self = key
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode("ctrl-\(keyName.lowercased())")
  }
}
