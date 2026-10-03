import Foundation

/// Everything the controller needs to run a session, handed over from the launcher as JSON.
public struct SessionPlan: Hashable, Codable, Sendable {
  public var configuration: Configuration
  public var hosts: [HostSpec]
  /// Path of the Unix socket sessions connect to.
  public var socketPath: String
  /// Keep windows open after their command ends, so errors stay visible.
  public var debug: Bool

  public init(
    configuration: Configuration, hosts: [HostSpec], socketPath: String, debug: Bool = false
  ) {
    self.configuration = configuration
    self.hosts = hosts
    self.socketPath = socketPath
    self.debug = debug
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  public static func decode(from data: Data) throws -> SessionPlan {
    try JSONDecoder().decode(SessionPlan.self, from: data)
  }
}

/// Builds the shell commands typed into new Terminal windows.
public struct WindowCommands: Hashable, Sendable {
  /// Absolute path of the tyssh executable.
  public var executable: String
  public var debug: Bool

  public init(executable: String, debug: Bool = false) {
    self.executable = executable
    self.debug = debug
  }

  public func controller(planPath: String) -> String {
    shellCommand([executable, "_controller", "--plan", planPath])
  }

  public func session(
    _ id: SessionID, host: HostSpec, socketPath: String, configuration: Configuration
  ) -> String {
    let ssh = host.sshArguments(
      ssh: configuration.ssh,
      extraArguments: configuration.sshArguments,
      defaultUser: configuration.login,
      defaultCommand: configuration.remoteCommand
    )
    return shellCommand(
      [
        executable, "_session", "--socket", socketPath, "--id", id.description, "--title",
        host.connectionString, "--",
      ]
        + ssh
    )
  }

  /// The command line for `words`.
  ///
  /// Normally the shell is replaced by the command, so the window's process ends
  /// with it. In debug mode the shell stays, keeping errors visible. The leading
  /// space keeps the command out of history where the shell ignores
  /// space-prefixed commands.
  func shellCommand(_ words: [String]) -> String {
    let command = ShellWords.join(words)
    return debug ? " \(command)" : " exec \(command)"
  }
}
