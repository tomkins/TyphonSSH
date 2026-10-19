/// Works out the areas session windows are tiled into, one per screen.
public enum TilingArea {
  /// - Parameters:
  ///   - selection: The configured screens (numbered from 1).
  ///   - screens: The visible frame of each display, main display first.
  public static func resolve(_ selection: ScreenSelection, screens: [Rect]) throws(TilingAreaError)
    -> [Rect]
  {
    switch selection {
    case .all:
      guard !screens.isEmpty else { throw .noSuchScreen(1, available: 0) }
      return screens
    case .screens(let numbers):
      return try numbers.map { number throws(TilingAreaError) in
        guard screens.indices.contains(number - 1) else {
          throw .noSuchScreen(number, available: screens.count)
        }
        return screens[number - 1]
      }
    }
  }

  /// The configured bounds if there are any, otherwise the selected screen(s).
  public static func resolve(for configuration: Configuration, screens: [Rect])
    throws(TilingAreaError) -> [Rect]
  {
    if let bounds = configuration.screenBounds { return [bounds] }
    return try resolve(configuration.screen, screens: screens)
  }
}

public enum TilingAreaError: Error, Equatable, CustomStringConvertible {
  case noSuchScreen(Int, available: Int)

  public var description: String {
    switch self {
    case .noSuchScreen(let number, let available):
      "No such screen [\(number)]; there \(available == 1 ? "is 1 screen" : "are \(available) screens")"
    }
  }
}
