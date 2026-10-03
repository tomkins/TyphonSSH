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
