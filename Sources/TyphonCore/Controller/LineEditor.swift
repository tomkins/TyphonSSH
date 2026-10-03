/// Minimal single-line editing for prompts typed into the controller while it is in raw mode.
public struct LineEditor: Hashable, Sendable {
  public private(set) var text: String

  public enum Outcome: Hashable, Sendable {
    case editing
    case submitted(String)
    case cancelled
  }

  public init(text: String = "") {
    self.text = text
  }

  public mutating func handle(_ key: Key) -> Outcome {
    switch key {
    case .character(let character):
      text.append(character)
    case .backspace, .control(0x08):
      _ = text.popLast()
    case .control(0x15):  // Ctrl-U
      text = ""
    case .control(0x17):  // Ctrl-W
      while text.last?.isWhitespace == true { text.removeLast() }
      while let last = text.last, !last.isWhitespace { text.removeLast() }
    case .enter:
      return .submitted(text.trimmingWhitespace().description)
    case .escape:
      return .cancelled
    default:
      break
    }
    return .editing
  }
}
