/// A single host to connect to, in the form `[user@]hostname[:port]`,
/// optionally paired with a command to run once connected.
public struct HostSpec: Hashable, Codable, Sendable {
  public var user: String?
  public var hostname: String
  public var port: Int?
  public var command: String?

  public init(user: String? = nil, hostname: String, port: Int? = nil, command: String? = nil) {
    self.user = user
    self.hostname = hostname
    self.port = port
    self.command = command
  }

  /// Parses `[user@]hostname[:port]`.
  public init(parsing string: String, command: String? = nil) throws(HostSpecError) {
    guard let parts = HostSpec.split(string) else {
      throw .malformed(string)
    }
    var port: Int?
    if let rawPort = parts.port {
      guard let value = Int(rawPort), (1...65535).contains(value) else {
        throw .invalidPort(string)
      }
      port = value
    }
    self.init(user: parts.user, hostname: parts.host, port: port, command: command)
  }

  /// The host as it was written: `user@hostname:port`, omitting absent parts.
  public var connectionString: String {
    var result = hostname
    if let user { result = "\(user)@\(result)" }
    if let port { result += ":\(port)" }
    return result
  }

  /// Builds the argument vector used to connect to this host.
  ///
  /// - Parameters:
  ///   - ssh: The ssh executable (or wrapper) to run.
  ///   - extraArguments: Additional arguments placed before the destination.
  ///   - defaultUser: Used when the spec itself names no user.
  ///   - defaultCommand: Used when the spec itself carries no command.
  public func sshArguments(
    ssh: String = "ssh",
    extraArguments: [String] = [],
    defaultUser: String? = nil,
    defaultCommand: String? = nil
  ) -> [String] {
    var arguments = [ssh] + extraArguments
    if let user = user ?? defaultUser, !user.isEmpty {
      arguments += ["-l", user]
    }
    if let port {
      arguments += ["-p", String(port)]
    }
    // End option parsing so the destination and command are never read as options.
    arguments += ["--", hostname]
    if let command = command ?? defaultCommand, !command.isEmpty {
      arguments.append(command)
    }
    return arguments
  }

  /// Splits `[user@]host[:rest]` without validating the port, so that patterns
  /// such as `host:[22,2222]` can be decomposed before expansion.
  static func split(_ string: String) -> (user: String?, host: String, port: String?)? {
    var remainder = Substring(string)
    var user: String?
    if let at = remainder.firstIndex(of: "@") {
      user = String(remainder[..<at])
      remainder = remainder[remainder.index(after: at)...]
      guard let user, !user.isEmpty, !user.hasPrefix("-") else { return nil }
    }
    var port: String?
    if let colon = remainder.firstIndex(of: ":") {
      port = String(remainder[remainder.index(after: colon)...])
      remainder = remainder[..<colon]
    }
    // A leading "-" would let a host smuggle options (such as -oProxyCommand) into ssh.
    guard !remainder.isEmpty, !remainder.hasPrefix("-"), !remainder.contains("@") else {
      return nil
    }
    return (user, String(remainder), port?.isEmpty == true ? nil : port)
  }
}

extension HostSpec: CustomStringConvertible {
  public var description: String { connectionString }
}

public enum HostSpecError: Error, Equatable, CustomStringConvertible {
  case malformed(String)
  case invalidPort(String)

  public var description: String {
    switch self {
    case .malformed(let spec): "Malformed host [\(spec)], expected [user@]host[:port]"
    case .invalidPort(let spec): "Invalid port in host [\(spec)]"
    }
  }
}
