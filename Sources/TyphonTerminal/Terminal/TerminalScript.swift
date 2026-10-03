import TyphonCore

/// AppleScript source for each Terminal.app operation.
///
/// Kept separate from execution so the generated scripts can be checked in tests.
enum TerminalScript {
  typealias Literal = AppleScriptLiteral

  /// Replies with a reference to the new tab, such as `tab 1 of window id 7801`.
  static func openWindow(running command: String) -> String {
    terminal(["return do script \(Literal.string(command))"])
  }

  static func windowID(forTTY tty: String) -> String {
    terminal([
      """
      repeat with w in windows
      	repeat with t in tabs of w
      		if tty of t is \(Literal.string(tty)) then return id of w
      	end repeat
      end repeat
      return missing value
      """
    ])
  }

  static func arrange(_ placements: [WindowPlacement]) -> String {
    terminal(
      placements.map { placement in
        """
        try
        	set w to window id \(placement.window)
        	set miniaturized of w to false
        	set visible of w to true
        	set bounds of w to \(Literal.bounds(placement.frame))
        	set frontmost of w to true
        end try
        """
      })
  }

  static func frame(of window: TerminalWindowID) -> String {
    terminal(["return bounds of window id \(window)"])
  }

  static func setFrame(_ frame: Rect, of window: TerminalWindowID) -> String {
    terminal(["set bounds of window id \(window) to \(Literal.bounds(frame))"])
  }

  static func colors(of window: TerminalWindowID) -> String {
    terminal([
      "set t to selected tab of window id \(window)",
      "return {normal text color of t, background color of t}",
    ])
  }

  static func setColors(_ colors: ColorPair, of window: TerminalWindowID) -> String {
    var lines = ["set t to selected tab of window id \(window)"]
    if let foreground = colors.foreground {
      lines.append("set normal text color of t to \(foreground.appleScriptLiteral)")
    }
    if let background = colors.background {
      lines.append("set background color of t to \(background.appleScriptLiteral)")
    }
    return terminal(lines)
  }

  static func setProfile(_ name: String, of window: TerminalWindowID) -> String {
    terminal([
      "set current settings of selected tab of window id \(window) to settings set \(Literal.string(name))"
    ])
  }

  static func set(_ property: String, to value: Bool, of windows: [TerminalWindowID]) -> String {
    terminal(windows.map { "try\n\tset \(property) of window id \($0) to \(value)\nend try" })
  }

  static func close(_ windows: [TerminalWindowID]) -> String {
    terminal(windows.map { "try\n\tclose window id \($0)\nend try" })
  }

  static func history(of window: TerminalWindowID) -> String {
    terminal(["return history of selected tab of window id \(window)"])
  }

  static func send(
    _ keystroke: Keystroke, to windows: [TerminalWindowID], thenFocus focus: TerminalWindowID?
  ) -> String {
    var lines = ["tell application \"Terminal\" to activate"]
    for window in windows {
      lines += [
        "tell application \"Terminal\" to set frontmost of window id \(window) to true",
        "delay 0.05",
        "tell application \"System Events\" to keystroke \(Literal.string(keystroke.key)) using {\(keystroke.modifiers.joined(separator: ", "))}",
        "delay 0.05",
      ]
    }
    if let focus {
      lines.append("tell application \"Terminal\" to set frontmost of window id \(focus) to true")
    }
    return lines.joined(separator: "\n")
  }

  private static func terminal(_ statements: [String]) -> String {
    let body =
      statements
      .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { "\t" + $0 }
      .joined(separator: "\n")
    return "tell application \"Terminal\"\n\(body)\nend tell"
  }
}

/// A key press sent through System Events.
struct Keystroke: Hashable {
  var key: String
  var modifiers: [String]

  init(for shortcut: TerminalShortcut) {
    switch shortcut {
    case .splitPane: self.init(key: "d", modifiers: ["command down"])
    case .closeSplitPane: self.init(key: "d", modifiers: ["command down", "shift down"])
    case .biggerFont: self.init(key: "+", modifiers: ["command down"])
    case .smallerFont: self.init(key: "-", modifiers: ["command down"])
    }
  }

  init(key: String, modifiers: [String]) {
    self.key = key
    self.modifiers = modifiers
  }
}
