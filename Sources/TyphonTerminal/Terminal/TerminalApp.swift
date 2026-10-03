import TyphonCore

/// Terminal's identifier for a window.
public typealias TerminalWindowID = Int

/// The window operations tyssh needs from a terminal application.
///
/// `AppleTerminal` drives Terminal.app; other terminals could be supported by
/// conforming to this protocol.
@MainActor
public protocol TerminalApp {
  /// Opens a new window running `command` in the user's shell.
  func openWindow(running command: String) throws -> TerminalWindowID
  /// Finds the window whose (any) tab is attached to `tty`, e.g. `/dev/ttys004`.
  func windowID(forTTY tty: String) throws -> TerminalWindowID?

  /// Un-hides, un-minimises and positions each window, bringing them forward in order.
  func arrange(_ placements: [WindowPlacement]) throws
  func frame(of window: TerminalWindowID) throws -> Rect
  func setFrame(_ frame: Rect, of window: TerminalWindowID) throws

  func colors(of window: TerminalWindowID) throws -> ColorPair
  /// Sets whichever colours are present in `colors`.
  func setColors(_ colors: ColorPair, of window: TerminalWindowID) throws
  /// Applies a Terminal profile ("settings set") by name.
  func setProfile(_ name: String, of window: TerminalWindowID) throws

  func hide(_ windows: [TerminalWindowID]) throws
  func minimize(_ windows: [TerminalWindowID]) throws
  func close(_ windows: [TerminalWindowID]) throws

  /// The full scrollback of the window's current tab.
  func history(of window: TerminalWindowID) throws -> String
  /// Sends a keyboard shortcut to each window in turn, then brings `focus` to the front.
  func send(
    _ shortcut: TerminalShortcut, to windows: [TerminalWindowID], thenFocus focus: TerminalWindowID?
  ) throws
}

public struct WindowPlacement: Hashable, Sendable {
  public var window: TerminalWindowID
  public var frame: Rect

  public init(window: TerminalWindowID, frame: Rect) {
    self.window = window
    self.frame = frame
  }
}

public enum TerminalError: Error, Equatable, CustomStringConvertible {
  case unexpectedResult(String)

  public var description: String {
    switch self {
    case .unexpectedResult(let what): "Unexpected reply from Terminal for \(what)"
    }
  }
}
