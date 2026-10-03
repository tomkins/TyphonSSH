import AppKit
import TyphonCore

/// Supplies the usable area of each display.
@MainActor
public protocol ScreenProvider {
  /// Visible frames (excluding the menu bar and Dock), main display first,
  /// in top-left-origin coordinates.
  func visibleFrames() -> [Rect]
}

public struct SystemScreens: ScreenProvider {
  public init() {}

  public func visibleFrames() -> [Rect] {
    let screens = NSScreen.screens
    guard let mainHeight = screens.first?.frame.height else { return [] }
    return screens.map { $0.visibleFrame.flipped(mainScreenHeight: mainHeight) }
  }
}

extension CGRect {
  /// Converts from AppKit's coordinates (origin at the bottom-left of the main
  /// display, y up) to the top-left-origin coordinates AppleScript uses.
  func flipped(mainScreenHeight: CGFloat) -> Rect {
    Rect(x: minX, y: mainScreenHeight - maxY, width: width, height: height)
  }
}
