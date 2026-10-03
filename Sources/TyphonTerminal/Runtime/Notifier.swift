/// Posts user-visible notifications, such as when a session closes.
@MainActor
public protocol Notifier {
  func notify(_ message: String)
}

/// Discards notifications.
public struct SilentNotifier: Notifier {
  public init() {}
  public func notify(_ message: String) {}
}

/// Posts notifications through Terminal, so they appear as coming from it.
///
/// A command-line tool has no app bundle, so it can't use the UserNotifications
/// framework directly. Failures are ignored; notifications are a nicety.
public struct TerminalNotifier: Notifier {
  private let runner: any AppleScriptRunner

  public init(runner: any AppleScriptRunner = NSAppleScriptRunner()) {
    self.runner = runner
  }

  public func notify(_ message: String) {
    _ = try? runner.run(Self.script(for: message))
  }

  nonisolated static func script(for message: String) -> String {
    "tell application \"Terminal\" to display notification \(AppleScriptLiteral.string(message)) with title \"tyssh\""
  }
}
