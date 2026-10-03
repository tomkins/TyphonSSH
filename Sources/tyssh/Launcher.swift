import Foundation
import TyphonCore
import TyphonTerminal

/// Hands a session over to a new controller window.
struct Launcher {
  var debug: Bool

  func launch(configuration: Configuration, hosts: [HostSpec]) async throws {
    let directory = try makePrivateDirectory()
    let plan = SessionPlan(
      configuration: configuration,
      hosts: hosts,
      socketPath: directory.appending(path: "control.sock").path,
      debug: debug
    )
    let planURL = directory.appending(path: "plan.json")
    try plan.encoded().write(to: planURL, options: .withoutOverwriting)

    let command = WindowCommands(executable: try executablePath(), debug: debug).controller(
      planPath: planURL.path)
    try await MainActor.run {
      _ = try AppleTerminal().openWindow(running: command)
    }
  }

  /// A fresh directory only the current user can enter, for the plan and socket.
  private func makePrivateDirectory() throws -> URL {
    var template = Array(
      FileManager.default.temporaryDirectory.appending(path: "tyssh.XXXXXX").path.utf8CString)
    guard let path = mkdtemp(&template) else {
      throw CocoaError(.fileWriteUnknown)
    }
    return URL(filePath: String(cString: path), directoryHint: .isDirectory)
  }

  private func executablePath() throws -> String {
    guard let url = Bundle.main.executableURL else { throw CocoaError(.executableNotLoadable) }
    return url.resolvingSymlinksInPath().path
  }
}
