/// A cell in the session grid, counted from the top-left.
public struct GridPosition: Hashable, Sendable {
  public var column: Int
  public var row: Int

  public init(column: Int, row: Int) {
    self.column = column
    self.row = row
  }
}

public enum Direction: Hashable, Sendable {
  case up, down, left, right
}

/// How session windows are tiled within the tiling area, with the controller
/// window running along the bottom.
///
/// Windows fill the grid row by row, so only the last row can be partly empty.
///
/// ```
/// ┌────────┬────────┬────────┐
/// │ 0      │ 1      │ 2      │
/// ├────────┼────────┼────────┤
/// │ 3      │ 4      │        │
/// ├────────┴────────┴────────┤
/// │ controller               │
/// └──────────────────────────┘
/// ```
public struct GridLayout: Hashable, Sendable {
  public let count: Int
  public let columns: Int
  public let area: Rect
  public let controllerHeight: Double

  /// - Parameters:
  ///   - count: Number of session windows.
  ///   - area: The whole tiling area, including the controller.
  ///   - columns: A fixed column count; takes precedence over `rows`.
  ///   - rows: A fixed row count, from which the columns are derived.
  public init(
    count: Int, area: Rect, controllerHeight: Double, columns: Int? = nil, rows: Int? = nil
  ) {
    self.count = count
    self.area = area
    self.controllerHeight = controllerHeight

    let chosen: Int
    if let columns, columns > 0 {
      chosen = columns
    } else if let rows, rows > 0 {
      chosen = (count + rows - 1) / rows
    } else {
      chosen = GridLayout.automaticColumns(for: count)
    }
    self.columns = min(max(chosen, 1), max(count, 1))
  }

  /// Picks a column count near √count that leaves the fewest empty cells,
  /// preferring an exact fit. Wider grids are tried first, since displays are
  /// landscape: three windows sit side by side rather than stacked.
  public static func automaticColumns(for count: Int) -> Int {
    guard count > 1 else { return 1 }
    let root = Int(Double(count).squareRoot().rounded(.up))
    var best = root
    var fewestEmpty = root
    for candidate in [root, root + 1, root - 1] where candidate > 0 {
      let remainder = count % candidate
      if remainder == 0 { return candidate }
      let empty = candidate - remainder
      if empty < fewestEmpty {
        fewestEmpty = empty
        best = candidate
      }
    }
    return best
  }

  public var rows: Int { max(1, (count + columns - 1) / columns) }

  public var cellWidth: Double { (area.width / Double(columns)).rounded(.down) }
  public var cellHeight: Double { ((area.height - controllerHeight) / Double(rows)).rounded(.down) }

  public func position(of index: Int) -> GridPosition {
    GridPosition(column: index % columns, row: index / columns)
  }

  /// The window index at `position`, or `nil` if that cell is empty or outside the grid.
  public func index(at position: GridPosition) -> Int? {
    guard (0..<columns).contains(position.column), (0..<rows).contains(position.row) else {
      return nil
    }
    let index = position.row * columns + position.column
    return index < count ? index : nil
  }

  public func frame(forWindowAt index: Int) -> Rect {
    let position = position(of: index)
    return Rect(
      x: area.x + Double(position.column) * cellWidth,
      y: area.y + Double(position.row) * cellHeight,
      width: cellWidth,
      height: cellHeight
    )
  }

  public var controllerFrame: Rect {
    Rect(x: area.x, y: area.maxY - controllerHeight, width: area.width, height: controllerHeight)
  }

  /// The frame for a single window filling everything above the controller.
  public var zoomedFrame: Rect {
    Rect(x: area.x, y: area.y, width: area.width, height: area.height - controllerHeight)
  }

  /// Moves from `index` one step in `direction`, wrapping at the edges and
  /// skipping the empty cells at the end of the last row.
  public func index(movingFrom index: Int, _ direction: Direction) -> Int {
    guard count > 0 else { return index }
    var position = position(of: index)
    repeat {
      switch direction {
      case .left: position.column = (position.column + columns - 1) % columns
      case .right: position.column = (position.column + 1) % columns
      case .up: position.row = (position.row + rows - 1) % rows
      case .down: position.row = (position.row + 1) % rows
      }
    } while self.index(at: position) == nil
    return self.index(at: position)!
  }
}
