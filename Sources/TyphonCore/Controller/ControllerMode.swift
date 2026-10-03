/// What the controller does with the next key press.
public enum ControllerMode: Hashable, Sendable {
  /// Keystrokes go to every enabled session.
  case input
  /// The action menu, entered with the action key.
  case action
  /// Choosing a session with the arrow keys to enable, disable or zoom it.
  case select(index: Int)
  /// Choosing the tiling area by moving and resizing the controller window.
  case bounds
  /// Sending a per-session string, such as each session's hostname.
  case sendText
  case sort
  case addHost(LineEditor)
  case dumpScrollback(LineEditor)
}

extension ControllerMode {
  /// The help text shown in the controller window.
  func prompt(actionKey: ControlKey, canEnableNext: Bool) -> [String] {
    switch self {
    case .input:
      return ["Input to terminal: (\(actionKey) to enter control mode)"]
    case .action:
      let enableNext = canEnableNext ? "[Space] enable next, " : ""
      return [
        "Actions (Esc to exit, \(actionKey) to send \(actionKey) to input)",
        "[c]reate window, [r]etile, s[o]rt, [e]nable/disable input, e[n]able all, \(enableNext)"
          + "[t]oggle enabled, [m]inimise, [h]ide, [s]end text, change [b]ounds, "
          + "[g/G]rid, [f/F]ont size, split [p/P]anes, clear s[k]rollback, "
          + "[d]ump scrollback, e[x]it",
      ]
    case .select:
      return [
        "Select window with arrow keys or h,j,k,l: (Esc to exit)",
        "[e]nable input, [d]isable input, disable [o]thers, disable [O]thers and zoom, [t]oggle input",
      ]
    case .bounds:
      return [
        "Move and resize this window to set the tiling area: (Enter to accept, Esc to cancel)",
        "Arrow keys or h,j,k,l move; hold Ctrl to resize. "
          + "[r]eset to default, [f]ill screen, [p]rint current bounds",
      ]
    case .sendText:
      return [
        "Send text to all enabled windows: (Esc to exit)",
        "[h]ostname, [c]onnection string, window [i]d, [s]ession id",
      ]
    case .sort:
      return ["Choose window order: (Esc to exit)", "[h]ostname, [i]d (order given)"]
    case .addHost(let editor):
      return ["Add hosts (names, patterns or clusters; Esc to cancel): \(editor.text)"]
    case .dumpScrollback(let editor):
      return [
        "Save scrollback to files named after this base, relative to your home folder "
          + "[\(ScrollbackFiles.defaultBaseName)]: \(editor.text)"
      ]
    }
  }
}
