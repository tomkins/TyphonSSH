import AppKit
import ApplicationServices
import TyphonCore

/// Moves and resizes Terminal windows.
///
/// Terminal's own AppleScript `bounds` can't be relied on for this when there
/// are several displays: it measures y from the top of the highest display
/// rather than the main one, so with a display above the main one, windows land
/// too high, often across two displays. Reading `bounds` is still accurate.
@MainActor
public protocol WindowMover {
  /// Places each window it can, returning the placements it couldn't make.
  func place(_ placements: [WindowPlacement]) -> [WindowPlacement]
}

/// Places windows through the Accessibility API, whose coordinates match
/// `Rect`'s. Needs the Accessibility permission; without it, nothing is placed.
public struct AccessibilityWindowMover: WindowMover {
  private let bundleIdentifier: String

  public init(bundleIdentifier: String = "com.apple.Terminal") {
    self.bundleIdentifier = bundleIdentifier
  }

  public func place(_ placements: [WindowPlacement]) -> [WindowPlacement] {
    guard !placements.isEmpty, AXIsProcessTrusted(),
      let app = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).first
    else { return placements }
    let windows = windowsByID(of: AXUIElementCreateApplication(app.processIdentifier))
    return placements.filter { placement in
      guard let window = windows[placement.window] else { return true }
      return !place(window, at: placement.frame)
    }
  }

  private func windowsByID(of app: AXUIElement) -> [TerminalWindowID: AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return [:] }
    var byID: [TerminalWindowID: AXUIElement] = [:]
    for window in windows {
      var id: CGWindowID = 0
      if _AXUIElementGetWindow(window, &id) == .success { byID[Int(id)] = window }
    }
    return byID
  }

  /// Sizes the window before and after moving it, because a window moving to a
  /// smaller display is shrunk to fit it on the way.
  private func place(_ window: AXUIElement, at frame: Rect) -> Bool {
    var origin = CGPoint(x: frame.x, y: frame.y)
    var size = CGSize(width: frame.width, height: frame.height)
    guard let position = AXValueCreate(.cgPoint, &origin), let size = AXValueCreate(.cgSize, &size)
    else { return false }
    let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    let resizedAgain = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
    return moved == .success && (resized == .success || resizedAgain == .success)
  }
}

/// The window number of an Accessibility window element, which is the same as
/// Terminal's window ID. Private, but long-standing and widely used.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>)
  -> AXError
