import Foundation
import System
import TyphonCore

/// Runs one session: ssh on its own pseudo-terminal, with input from both the
/// window's keyboard and the controller.
///
/// ```
///  keyboard ─┐
///            ├─▶ pty ─▶ ssh
/// controller ┘     └──▶ window
/// ```
public struct SessionRuntime: Sendable {
  public var id: SessionID
  public var title: String
  public var socketPath: String
  /// Proves to the controller that this is the session it started.
  public var token: String
  /// The ssh invocation, starting with the executable.
  public var command: [String]

  public init(id: SessionID, title: String, socketPath: String, token: String, command: [String]) {
    self.id = id
    self.title = title
    self.socketPath = socketPath
    self.token = token
    self.command = command
  }

  /// Runs until ssh exits, returning its exit code.
  public func run() async throws -> Int32 {
    let output = TerminalOutput()
    output.clearAll()
    output.setTitle("tyssh - \(title)")

    let controller = try MessageConnection.connect(to: socketPath)
    controller.send(.hello(id: id, tty: ttyName(.standardInput) ?? "", token: token))

    let rawMode = FileDescriptor.standardInput.isTerminal ? try RawMode() : nil

    let ssh = try PseudoTerminal(
      arguments: command, size: FileDescriptor.standardInput.terminalSize ?? .default)

    let exitStatus = await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for await chunk in FileDescriptor.standardInput.chunks() {
          try? ssh.send(chunk)
        }
      }
      group.addTask {
        for await message in controller.messages() {
          if case .input(let data) = message { try? ssh.send(data) }
        }
        // The controller has gone: hang up, as closing a terminal would.
        kill(ssh.processID, SIGHUP)
      }
      group.addTask {
        for await _ in signalEvents(SIGWINCH) {
          if let size = FileDescriptor.standardInput.terminalSize { try? ssh.resize(to: size) }
        }
      }

      // Drain ssh's output (including any parting message) before collecting its status.
      for await chunk in ssh.output() { output.write(chunk) }
      let status = await ssh.waitForExit()
      group.cancelAll()
      return status
    }
    controller.send(.exited(code: exitStatus.code))
    controller.close()
    _ = consume rawMode  // Restore the terminal now, not whenever the optimiser decides.
    return exitStatus.code
  }
}

/// The path of the terminal device attached to `descriptor`, e.g. `/dev/ttys004`.
public func ttyName(_ descriptor: FileDescriptor) -> String? {
  ttyname(descriptor.rawValue).map { String(cString: $0) }
}
