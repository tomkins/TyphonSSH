import ArgumentParser
import Foundation
import TyphonCore
import TyphonTerminal

/// The launcher: what users run.
struct Tyssh: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tyssh",
    abstract: "Cluster SSH for Terminal.app: type once, run everywhere.",
    usage: "tyssh [<options>] <hosts> ...",
    discussion: """
      Opens a Terminal window per host, tiled above a controller window. Whatever \
      you type in the controller is sent to every enabled host.

      Press Ctrl-A in the controller for actions: re-tile, add hosts, enable or \
      disable hosts, zoom, change the tiling area, and more.

      Configuration is read from ~/.config/tyssh/config.json.
      """,
    version: typhonVersion
  )

  @OptionGroup var options: LaunchOptions

  @Argument(
    help:
      "Hosts to connect to: [user@]host[:port], patterns such as web[1-4] or 10.0.0.0/28, or cluster names.",
    completion: .custom { _, _, _ in clusterNames() }
  )
  var hosts: [String] = []

  func validate() throws {
    if let columns = options.columns, columns < 1 {
      throw ValidationError("--columns must be at least 1")
    }
    if let rows = options.rows, rows < 1 { throw ValidationError("--rows must be at least 1") }
    if let sessionMax = options.sessionMax, sessionMax < 1 {
      throw ValidationError("--session-max must be at least 1")
    }
  }

  func run() async throws {
    let configuration = try ConfigurationLoader().load(
      additionalFiles: options.configFiles.map { URL(filePath: $0) },
      overrides: try options.overrides()
    )

    if options.listClusters {
      for name in configuration.clusters.keys.sorted() { print(name) }
      return
    }

    let entries = try options.hostsFiles.flatMap { path in
      HostsFile.parse(try readHostsFile(path))
    }
    var resolvedHosts = try HostListResolver(configuration: configuration)
      .resolve(arguments: hosts, hostsFileEntries: entries)
    if configuration.sortHosts {
      resolvedHosts = resolvedHosts.sortedByName()
    }
    resolvedHosts = resolvedHosts.interleaved(by: configuration.interleave)

    try await Launcher(debug: options.debug).launch(
      configuration: configuration, hosts: resolvedHosts)
  }

  private func readHostsFile(_ path: String) throws -> String {
    if path == "-" {
      return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }
    return try String(contentsOfFile: path, encoding: .utf8)
  }
}

/// Cluster names from the default configuration, for shell completion.
@Sendable func clusterNames() -> [String] {
  ((try? ConfigurationLoader().load())?.clusters.keys.sorted()) ?? []
}

extension ScreenSelection: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(argument)
  }
}
