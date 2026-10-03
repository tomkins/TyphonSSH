import Foundation
import System

/// Escape sequences tyssh writes to its own terminal.
public struct TerminalOutput: Sendable {
  private let descriptor: FileDescriptor

  public init(_ descriptor: FileDescriptor = .standardOutput) {
    self.descriptor = descriptor
  }

  public func write(_ data: some Sequence<UInt8>) {
    _ = try? descriptor.writeAll(data)
  }

  public func write(_ string: String) {
    write(Array(string.utf8))
  }

  /// Clears the screen and shows `lines` from the top-left. In raw mode a
  /// newline doesn't return the cursor, so lines are separated by CR LF.
  public func show(_ lines: [String]) {
    write("\u{1B}[H\u{1B}[2J" + lines.joined(separator: "\r\n"))
  }

  /// Clears the screen and the scrollback, e.g. to hide the command that started us.
  public func clearAll() {
    write("\u{1B}[H\u{1B}[2J\u{1B}[3J")
  }

  public func setTitle(_ title: String) {
    write("\u{1B}]0;\(title)\u{07}")
  }

  public func bell() {
    write("\u{07}")
  }
}
