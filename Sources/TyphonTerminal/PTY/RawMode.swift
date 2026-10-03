import Foundation
import System

/// Puts a terminal into raw mode for the lifetime of the value, restoring the
/// original settings when it goes out of scope.
///
/// In raw mode every byte typed is delivered immediately, unechoed and
/// uninterpreted, so Ctrl-C, Ctrl-Z and friends reach the remote hosts.
public struct RawMode: ~Copyable {
  private let descriptor: FileDescriptor
  private let original: termios

  public init(_ descriptor: FileDescriptor = .standardInput) throws(Errno) {
    var original = termios()
    guard tcgetattr(descriptor.rawValue, &original) == 0 else { throw Errno(rawValue: errno) }

    var raw = original
    cfmakeraw(&raw)
    guard tcsetattr(descriptor.rawValue, TCSAFLUSH, &raw) == 0 else { throw Errno(rawValue: errno) }

    self.descriptor = descriptor
    self.original = original
  }

  deinit {
    var settings = original
    tcsetattr(descriptor.rawValue, TCSAFLUSH, &settings)
  }
}
