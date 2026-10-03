import Foundation

/// Reads configuration files and layers them over the defaults.
public struct ConfigurationLoader: Sendable {
  /// Returns a file's contents, or `nil` if it does not exist.
  public typealias FileReader = @Sendable (URL) throws -> Data?

  private let readFile: FileReader

  public init(readFile: @escaping FileReader = ConfigurationLoader.readFromDisk) {
    self.readFile = readFile
  }

  /// The default configuration file: `$XDG_CONFIG_HOME/tyssh/config.json`,
  /// falling back to `~/.config/tyssh/config.json`.
  public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> URL
  {
    let base =
      environment["XDG_CONFIG_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: ".config", directoryHint: .isDirectory)
    return base.appending(path: "tyssh/config.json")
  }

  /// Loads the configuration.
  ///
  /// - Parameters:
  ///   - defaultFile: Read if present; silently skipped if missing.
  ///   - additionalFiles: Files named explicitly (e.g. with `--config`); these must exist.
  ///   - overrides: Applied last, typically from command-line options.
  public func load(
    defaultFile: URL? = ConfigurationLoader.defaultURL(),
    additionalFiles: [URL] = [],
    overrides: Configuration.Overrides = .init()
  ) throws(ConfigurationError) -> Configuration {
    var configuration = Configuration()
    if let defaultFile, let layer = try layer(at: defaultFile, required: false) {
      configuration = configuration.applying(layer)
    }
    for file in additionalFiles {
      if let layer = try layer(at: file, required: true) {
        configuration = configuration.applying(layer)
      }
    }
    return configuration.applying(overrides)
  }

  private func layer(at url: URL, required: Bool) throws(ConfigurationError) -> Configuration
    .Overrides?
  {
    let data: Data?
    do {
      data = try readFile(url)
    } catch {
      throw .unreadable(url.path, reason: error.localizedDescription)
    }
    guard let data else {
      if required { throw .missing(url.path) }
      return nil
    }
    do {
      return try JSONDecoder().decode(Configuration.Overrides.self, from: data)
    } catch let error as DecodingError {
      throw .invalid(url.path, reason: error.summary)
    } catch {
      throw .invalid(url.path, reason: error.localizedDescription)
    }
  }

  public static let readFromDisk: FileReader = { url in
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try Data(contentsOf: url)
  }
}

public enum ConfigurationError: Error, Equatable, CustomStringConvertible {
  case missing(String)
  case unreadable(String, reason: String)
  case invalid(String, reason: String)

  public var description: String {
    switch self {
    case .missing(let path): "Configuration file not found: \(path)"
    case .unreadable(let path, let reason): "Can't read \(path): \(reason)"
    case .invalid(let path, let reason): "Invalid configuration in \(path): \(reason)"
    }
  }
}

extension DecodingError {
  /// A one-line explanation naming the offending key path.
  var summary: String {
    func path(_ context: Context) -> String {
      let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(
        separator: ".")
      return path.isEmpty ? "" : "\(path): "
    }
    switch self {
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
      return path(context)
        + (context.underlyingError.map { "\($0.localizedDescription)" } ?? context.debugDescription)
    case .keyNotFound(let key, let context):
      return path(context) + "missing key \(key.stringValue)"
    @unknown default:
      return localizedDescription
    }
  }
}
