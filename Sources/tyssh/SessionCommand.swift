import ArgumentParser
import TyphonCore
import TyphonTerminal

/// Runs in each session window, wrapping ssh.
struct SessionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "_session",
    abstract: "Run one session window (started by the controller)."
  )

  @Option(help: "The controller's socket.")
  var socket: String

  @Option(help: "This session's identifier.")
  var id: Int

  @Option(help: "The secret proving this session to the controller.")
  var token: String

  @Option(help: "Window title.")
  var title: String

  @Argument(parsing: .postTerminator, help: "The ssh command line.")
  var command: [String]

  func validate() throws {
    guard !command.isEmpty else { throw ValidationError("Missing the command to run after --") }
  }

  func run() async throws {
    let runtime = SessionRuntime(
      id: SessionID(id), title: title, socketPath: socket, token: token, command: command)
    throw ExitCode(try await runtime.run())
  }
}
