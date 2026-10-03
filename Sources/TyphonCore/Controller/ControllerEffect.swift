import Foundation

/// Something the controller runtime must do in response to input.
///
/// `ControllerState` decides *what* should happen; effects carry those decisions
/// to the code that talks to Terminal, sockets and the file system.
public enum ControllerEffect: Hashable, Sendable {
  /// Feed bytes to sessions as if typed there.
  case send(Data, to: [SessionID])
  /// Open a window for a new session.
  case openSession(SessionID, HostSpec)
  /// Lay out every window according to the state's current grid; also un-hides,
  /// un-minimises and un-zooms them.
  case retile
  /// Expand one session to fill the area above the controller.
  case zoom(SessionID)
  /// Recolour a session window.
  case setAppearance(SessionID, SessionAppearance)
  case hideSessions
  case minimizeSessions
  case minimizeController
  /// Send a Terminal keyboard shortcut to the given sessions, and optionally the controller.
  case shortcut(TerminalShortcut, sessions: [SessionID], includingController: Bool)
  /// Write each session's scrollback to the given path (relative to the home directory).
  case dumpScrollback([ScrollbackDump])
  case bounds(BoundsCommand)
  case notify(String)
  case bell
  /// Close every session window and exit.
  case quit
}

public struct ScrollbackDump: Hashable, Sendable {
  public var session: SessionID
  public var path: String

  public init(session: SessionID, path: String) {
    self.session = session
    self.path = path
  }
}

/// Terminal.app commands that are only reachable through the keyboard.
public enum TerminalShortcut: Hashable, Sendable {
  case splitPane
  case closeSplitPane
  case biggerFont
  case smallerFont
}

/// Steps in interactively choosing the tiling area by moving the controller window.
public enum BoundsCommand: Hashable, Sendable {
  /// Expand the controller to the current tiling area and hide the sessions.
  case begin
  case move(Direction)
  case resize(Direction)
  /// Use the controller's current frame as the tiling area.
  case accept
  /// Keep the previous tiling area.
  case cancel
  /// Return to the configured tiling area.
  case reset
  /// Use the whole of the configured screen(s).
  case fillScreen
  /// Show the current frame in a form that can be pasted into the configuration.
  case print
}
