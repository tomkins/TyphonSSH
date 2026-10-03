/// One line of a hosts file: a host pattern, optionally followed by a command to run there.
public struct HostsFileEntry: Hashable, Sendable {
  public var pattern: String
  public var command: String?

  public init(pattern: String, command: String? = nil) {
    self.pattern = pattern
    self.command = command
  }
}

/// The plain-text hosts file format accepted by `--hosts`:
///
/// ```
/// # Comments start with a hash
/// web[1-3]           uptime
/// username@db1:2222      tail -f /var/log/postgresql.log
/// cache1
/// ```
public enum HostsFile {
  public static func parse(_ text: String) -> [HostsFileEntry] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
      let content = line.prefix { $0 != "#" }.trimmingWhitespace()
      guard !content.isEmpty else { return nil }
      guard let space = content.firstIndex(where: \.isWhitespace) else {
        return HostsFileEntry(pattern: String(content))
      }
      let command = content[space...].trimmingWhitespace()
      return HostsFileEntry(
        pattern: String(content[..<space]), command: command.isEmpty ? nil : String(command))
    }
  }
}

extension StringProtocol {
  func trimmingWhitespace() -> SubSequence {
    let start = firstIndex { !$0.isWhitespace } ?? endIndex
    let end = lastIndex { !$0.isWhitespace }.map(index(after:)) ?? start
    return self[start..<end]
  }
}
