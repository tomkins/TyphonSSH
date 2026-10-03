import ArgumentParser
import TyphonCore

/// Command-line options, each overriding the corresponding configuration setting.
struct LaunchOptions: ParsableArguments {
  @Option(name: [.short, .long], help: "User for hosts that don't name one.")
  var login: String?

  @Option(
    name: [.customShort("c"), .customLong("config")],
    help: "An additional configuration file. Repeatable.")
  var configFiles: [String] = []

  @Option(name: [.customShort("x"), .long], help: "Number of grid columns.")
  var columns: Int?

  @Option(
    name: [.customShort("y"), .long], help: "Number of grid rows (ignored if --columns is given).")
  var rows: Int?

  @Option(help: "Screen to tile on, numbered from 1, or a span such as 1-2.")
  var screen: ScreenSelection?

  @Option(help: "The ssh command to run.")
  var ssh: String?

  @Option(
    name: .customLong("ssh-args"),
    help: "Extra arguments for ssh, e.g. \"-A -o ServerAliveInterval=30\".")
  var sshArguments: String?

  @Option(help: "Command to run on hosts that don't have their own.")
  var remoteCommand: String?

  @Option(
    name: .customLong("hosts"),
    help:
      "A file listing hosts (and optionally a command for each); - reads standard input. Repeatable."
  )
  var hostsFiles: [String] = []

  @Option(help: "The most sessions to open.")
  var sessionMax: Int?

  @Flag(help: "Sort hosts by name.")
  var sortHosts = false

  @Option(
    name: [.short, .long], help: "Interleave hosts, taking every Nth so clusters sit side by side.")
  var interleave: Int?

  @Option(help: "Terminal profile for the controller window.")
  var controllerProfile: String?

  @Option(help: "Terminal profile for session windows.")
  var sessionProfile: String?

  @Flag(inversion: .prefixedNo, help: "Post notifications when sessions close or input moves.")
  var notifications: Bool?

  @Flag(help: "List the configured cluster names and exit.")
  var listClusters = false

  @Flag(help: "Keep windows open after their command ends, so errors stay visible.")
  var debug = false

  func overrides() throws -> Configuration.Overrides {
    var overrides = Configuration.Overrides()
    overrides.login = login
    overrides.tileColumns = columns
    overrides.tileRows = rows
    overrides.screen = screen
    overrides.ssh = ssh
    overrides.sshArguments = try sshArguments.map { try ShellWords.split($0) }
    overrides.remoteCommand = remoteCommand
    overrides.sessionMax = sessionMax
    overrides.sortHosts = sortHosts ? true : nil
    overrides.interleave = interleave
    overrides.controllerProfile = controllerProfile
    overrides.sessionProfile = sessionProfile
    overrides.notifications = notifications
    return overrides
  }
}
