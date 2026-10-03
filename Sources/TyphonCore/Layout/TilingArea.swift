/// Works out the area session windows are tiled into.
public enum TilingArea {
  /// - Parameters:
  ///   - selection: The configured screen or screen span (numbered from 1).
  ///   - screens: The visible frame of each display, main display first.
  public static func resolve(_ selection: ScreenSelection, screens: [Rect]) throws(TilingAreaError)
    -> Rect
  {
    func screen(_ number: Int) throws(TilingAreaError) -> Rect {
      guard screens.indices.contains(number - 1) else {
        throw .noSuchScreen(number, available: screens.count)
      }
      return screens[number - 1]
    }
    switch selection {
    case .single(let number):
      return try screen(number)
    case .span(let first, let second):
      return Rect.spanning(try screen(first), try screen(second))
    }
  }

  /// The configured bounds if there are any, otherwise the selected screen(s).
  public static func resolve(for configuration: Configuration, screens: [Rect])
    throws(TilingAreaError) -> Rect
  {
    if let bounds = configuration.screenBounds { return bounds }
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
