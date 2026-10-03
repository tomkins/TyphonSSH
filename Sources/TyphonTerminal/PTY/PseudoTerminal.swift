import CTyphonSupport
import Foundation
import System

/// A process running on its own pseudo-terminal.
///
/// Whatever is written to the pseudo-terminal arrives as the process's keyboard
/// input; whatever the process prints can be read back. tyssh runs ssh this
/// way so that keystrokes broadcast from the controller can be fed in
/// alongside those typed directly into a session window.
public final class PseudoTerminal: Sendable {
  public let processID: pid_t
  /// The primary (controlling) side of the pseudo-terminal.
  public let primary: FileDescriptor

  /// Starts `arguments[0]`, found on `PATH`, with the remaining arguments.
  public init(arguments: [String], size: TerminalSize = .default) throws(Errno) {
    precondition(!arguments.isEmpty, "A command is required")

    // Build argv before forking: the child must not allocate.
    let argv = arguments.map { strdup($0) } + [nil]
    defer { for pointer in argv { free(pointer) } }

    var descriptor: Int32 = -1
    let pid = argv.withUnsafeBufferPointer {
      typhon_spawn_pty($0.baseAddress!, size.rows, size.columns, &descriptor)
    }
    guard pid > 0 else { throw Errno(rawValue: errno) }

    self.processID = pid
    self.primary = FileDescriptor(rawValue: descriptor)
  }

  /// Output from the process, ending when it closes the terminal.
  public func output() -> AsyncStream<Data> {
    primary.chunks()
  }

  /// Feeds bytes to the process as if typed.
  public func send(_ data: some DataProtocol) throws {
    try primary.writeAll(data)
  }

  /// Tells the process its terminal changed size (it receives `SIGWINCH`).
  public func resize(to size: TerminalSize) throws(Errno) {
    try primary.setTerminalSize(size)
  }

  public var size: TerminalSize? { primary.terminalSize }

  public func waitForExit() async -> ExitStatus {
    await TyphonTerminal.waitForExit(of: processID)
  }

  deinit {
    try? primary.close()
  }
}
