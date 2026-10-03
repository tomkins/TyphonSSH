/// A key press read from the controller's terminal in raw mode.
public enum Key: Hashable, Sendable {
  /// A printable character.
  case character(Character)
  /// A control chord, carrying the byte sent (e.g. `0x01` for Ctrl-A).
  case control(UInt8)
  case enter
  case escape
  case backspace
  /// An arrow key; `modified` when held with Ctrl (or another modifier).
  case arrow(Direction, modified: Bool)
  /// An escape sequence we don't interpret.
  case unknown([UInt8])
}

/// Decodes raw terminal input into `Key`s.
///
/// Escape sequences are decoded within a single read. A lone ESC at the end of
/// a read is the Escape key: terminals deliver a whole sequence in one write,
/// so this is reliable for interactive input.
public enum KeyDecoder {
  public static func keys(in bytes: some Sequence<UInt8>) -> [Key] {
    var input = ArraySlice(bytes)
    var keys: [Key] = []
    while let key = next(from: &input) {
      keys.append(key)
    }
    return keys
  }

  /// Decodes and consumes one key from the front of `input`.
  ///
  /// Note that Ctrl-H arrives as `.control(0x08)`; the Delete key sends `.backspace`.
  public static func next(from input: inout ArraySlice<UInt8>) -> Key? {
    guard let byte = input.popFirst() else { return nil }
    switch byte {
    case 0x1B: return escapeSequence(from: &input)
    case 0x0D: return .enter
    case 0x7F: return .backspace
    case 0x00..<0x20: return .control(byte)
    case 0x20..<0x80: return .character(Character(Unicode.Scalar(byte)))
    default: return utf8Character(startingWith: byte, from: &input)
    }
  }

  /// Decodes what follows an ESC byte, consuming it from `input`.
  private static func escapeSequence(from input: inout ArraySlice<UInt8>) -> Key {
    switch input.first {
    case UInt8(ascii: "["):
      // CSI: parameter bytes, then a final byte in 0x40...0x7E.
      guard let finalIndex = input.dropFirst().firstIndex(where: { (0x40...0x7E).contains($0) })
      else {
        return .escape
      }
      let sequence = input[...finalIndex]
      input = input[(finalIndex + 1)...]
      if let direction = direction(for: sequence.last!) {
        // `ESC [ 5 C` (csshX-era) and `ESC [ 1 ; 5 C` (xterm) both mean a modifier was held.
        return .arrow(direction, modified: sequence.count > 2)
      }
      return .unknown([0x1B] + sequence)
    case UInt8(ascii: "O") where input.count >= 2:
      let sequence = input.prefix(2)
      input = input.dropFirst(2)
      if let direction = direction(for: sequence.last!) {
        return .arrow(direction, modified: false)
      }
      return .unknown([0x1B] + sequence)
    default:
      return .escape
    }
  }

  private static func direction(for finalByte: UInt8) -> Direction? {
    switch finalByte {
    case UInt8(ascii: "A"): .up
    case UInt8(ascii: "B"): .down
    case UInt8(ascii: "C"): .right
    case UInt8(ascii: "D"): .left
    default: nil
    }
  }

  private static func utf8Character(startingWith lead: UInt8, from input: inout ArraySlice<UInt8>)
    -> Key
  {
    let continuationCount =
      switch lead {
      case 0xC0..<0xE0: 1
      case 0xE0..<0xF0: 2
      case 0xF0..<0xF8: 3
      default: 0
      }
    let sequence = [lead] + input.prefix(continuationCount)
    input = input.dropFirst(continuationCount)
    guard let character = String(validating: sequence, as: UTF8.self)?.first else {
      return .unknown(sequence)
    }
    return .character(character)
  }
}

extension KeyDecoder {
  /// Rewrites cursor keys from CSI form (`ESC [ A`) to SS3 form (`ESC O A`).
  ///
  /// The controller's terminal is in normal cursor mode, but full-screen programs
  /// on the remote hosts (vim, less, top) put their terminals into application
  /// mode and expect SS3. Readline accepts both, so SS3 works everywhere.
  public static func applicationCursorKeys(_ bytes: [UInt8]) -> [UInt8] {
    var result: [UInt8] = []
    result.reserveCapacity(bytes.count)
    var index = 0
    while index < bytes.count {
      if index + 2 < bytes.count, bytes[index] == 0x1B, bytes[index + 1] == UInt8(ascii: "["),
        direction(for: bytes[index + 2]) != nil
      {
        result += [0x1B, UInt8(ascii: "O"), bytes[index + 2]]
        index += 3
      } else {
        result.append(bytes[index])
        index += 1
      }
    }
    return result
  }
}
