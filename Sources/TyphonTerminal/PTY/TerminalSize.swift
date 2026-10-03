import CTyphonSupport
import Darwin
import System

/// The size of a terminal, in character cells.
public struct TerminalSize: Hashable, Sendable {
  public var rows: UInt16
  public var columns: UInt16

  public init(rows: UInt16, columns: UInt16) {
    self.rows = rows
    self.columns = columns
  }

  public static let `default` = TerminalSize(rows: 24, columns: 80)
}

extension FileDescriptor {
  /// The size of the terminal this descriptor refers to, or `nil` if it isn't a terminal.
  public var terminalSize: TerminalSize? {
    var rows: UInt16 = 0
    var columns: UInt16 = 0
    guard typhon_get_window_size(rawValue, &rows, &columns) == 0, rows > 0, columns > 0 else {
      return nil
    }
    return TerminalSize(rows: rows, columns: columns)
  }

  public func setTerminalSize(_ size: TerminalSize) throws(Errno) {
    guard typhon_set_window_size(rawValue, size.rows, size.columns) == 0 else {
      throw Errno(rawValue: errno)
    }
  }

  public var isTerminal: Bool { isatty(rawValue) == 1 }
}
