import ArgumentParser
import Foundation
import System
import TyphonCore
import TyphonTerminal

/// Runs in the controller window that the launcher opens.
struct ControllerCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "_controller",
    abstract: "Run the controller window (started by tyssh)."
  )

  @Option(help: "The session plan written by the launcher.")
  var plan: String

  func run() async throws {
    let planURL = URL(filePath: plan)
    let plan = try SessionPlan.decode(from: Data(contentsOf: planURL))
    try? FileManager.default.removeItem(at: planURL)
    // Remove only what the launcher created, and the directory only once it's
    // empty: never delete recursively on the strength of a path argument.
    defer {
      unlink(plan.socketPath)
      rmdir(planURL.deletingLastPathComponent().path)
    }

    let listener = try MessageListener(path: plan.socketPath)
    let rawMode = try RawMode()
    await Self.runController(plan: plan, listener: listener)
    _ = consume rawMode
  }

  @MainActor
  private static func runController(plan: SessionPlan, listener: MessageListener) async {
    let environment = ControllerRuntime.Environment(
      terminal: AppleTerminal(),
      screens: SystemScreens(),
      notifier: TerminalNotifier(),
      output: TerminalOutput(),
      commands: WindowCommands(
        executable: Bundle.main.executableURL?.resolvingSymlinksInPath().path
          ?? CommandLine.arguments[0],
        debug: plan.debug
      )
    )
    await ControllerRuntime(plan: plan, environment: environment).run(listener: listener)
  }
}
