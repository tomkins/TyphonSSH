/// The visual state of a session window, from which its colours are derived.
public struct SessionAppearance: Hashable, Sendable {
  public var isEnabled: Bool
  public var isSelected: Bool

  public init(isEnabled: Bool = true, isSelected: Bool = false) {
    self.isEnabled = isEnabled
    self.isSelected = isSelected
  }

  /// The colours a window should show, given the scheme and the colours it had originally.
  ///
  /// Selection takes precedence for the background, so the cursor is visible
  /// over disabled windows; disabled takes precedence for the foreground, so
  /// you can still tell a selected window won't receive input.
  public func colors(scheme: ColorScheme, original: ColorPair) -> ColorPair {
    let selected = isSelected ? scheme.selected : ColorPair()
    let disabled = isEnabled ? ColorPair() : scheme.disabled
    return ColorPair(
      foreground: disabled.foreground ?? selected.foreground ?? original.foreground,
      background: selected.background ?? disabled.background ?? original.background
    )
  }
}
