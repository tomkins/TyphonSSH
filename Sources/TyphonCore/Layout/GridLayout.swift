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

/// The arrangement of session windows into rows and columns.
///
/// Windows fill the grid row by row, so only the last row can be partly empty.
public struct GridShape: Hashable, Sendable {
  public let count: Int
  public let columns: Int

  /// - Parameters:
  ///   - count: Number of session windows.
  ///   - columns: A fixed column count; takes precedence over `rows`.
  ///   - rows: A fixed row count, from which the columns are derived.
  public init(count: Int, columns: Int? = nil, rows: Int? = nil) {
    self.count = count
    let chosen: Int
    if let columns, columns > 0 {
      chosen = columns
    } else if let rows, rows > 0 {
      chosen = (count + rows - 1) / rows
    } else {
      chosen = GridShape.automaticColumns(for: count)
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

/// The session windows shared out between one grid per tiling area (usually
/// one per screen), filling the first grid, then the next, and so on.
public struct Tiling: Hashable, Sendable {
  public let grids: [GridShape]

  public init(grids: [GridShape]) {
    self.grids = grids.isEmpty ? [GridShape(count: 0)] : grids
  }

  /// - Parameters:
  ///   - count: Number of session windows.
  ///   - weights: The relative size of each tiling area; windows are shared
  ///     out in proportion, so they come out about the same size everywhere.
  ///   - columns: A fixed column count for every grid; see `GridShape`.
  ///   - rows: A fixed row count for every grid; see `GridShape`.
  public init(count: Int, weights: [Double] = [1], columns: Int? = nil, rows: Int? = nil) {
    self.init(
      grids: Tiling.share(count, by: weights).map {
        GridShape(count: $0, columns: columns, rows: rows)
      })
  }

  /// Divides `count` in proportion to `weights` by the largest remainder
  /// method, favouring earlier weights in a tie.
  public static func share(_ count: Int, by weights: [Double]) -> [Int] {
    let weights = weights.isEmpty ? [1] : weights.map { max($0, 0) }
    let total = weights.reduce(0, +)
    guard total > 0 else { return [count] + Array(repeating: 0, count: weights.count - 1) }
    let exact = weights.map { Double(count) * $0 / total }
    var shares = exact.map { Int($0.rounded(.down)) }
    let remainders = exact.indices.sorted {
      (exact[$0] - Double(shares[$0]), -$0) > (exact[$1] - Double(shares[$1]), -$1)
    }
    for index in remainders.prefix(count - shares.reduce(0, +)) { shares[index] += 1 }
    return shares
  }

  public var count: Int { grids.reduce(0) { $0 + $1.count } }

  /// The grid holding the window at `index`, and the window's index within that grid.
  public func locate(_ index: Int) -> (grid: Int, index: Int)? {
    guard index >= 0 else { return nil }
    var first = 0
    for (grid, shape) in grids.enumerated() {
      if index < first + shape.count { return (grid, index - first) }
      first += shape.count
    }
    return nil
  }

  private func firstIndex(ofGrid grid: Int) -> Int {
    grids[..<grid].reduce(0) { $0 + $1.count }
  }

  /// Moves from `index` one step in `direction`. Up and down wrap within a
  /// grid; left and right carry on into the neighbouring grid at the same row,
  /// wrapping from the last grid to the first.
  public func index(movingFrom index: Int, _ direction: Direction) -> Int {
    guard let (grid, local) = locate(index) else { return index }
    let filled = grids.indices.filter { grids[$0].count > 0 }
    let shape = grids[grid]
    let step: Int
    switch direction {
    case .left: step = -1
    case .right: step = 1
    case .up, .down: step = 0
    }
    var position = shape.position(of: local)
    position.column += step
    if step == 0 || filled.count == 1 || shape.index(at: position) != nil {
      return firstIndex(ofGrid: grid) + shape.index(movingFrom: local, direction)
    }
    let here = filled.firstIndex(of: grid)!
    let next = filled[(here + step + filled.count) % filled.count]
    let target = grids[next]
    let row = min(position.row, target.rows - 1)
    let column = step > 0 ? 0 : min(target.columns, target.count - row * target.columns) - 1
    return firstIndex(ofGrid: next) + target.index(at: GridPosition(column: column, row: row))!
  }
}

/// Where each window goes: each grid of a `Tiling` placed in its own tiling
/// area, with the controller window running along the bottom of the first.
///
/// ```
/// ┌────────┬────────┬────────┐  ┌────────┬────────┐
/// │ 0      │ 1      │ 2      │  │ 5      │ 6      │
/// ├────────┼────────┼────────┤  │        │        │
/// │ 3      │ 4      │        │  ├────────┼────────┤
/// ├────────┴────────┴────────┤  │ 7      │        │
/// │ controller               │  │        │        │
/// └──────────────────────────┘  └────────┴────────┘
/// ```
public struct GridLayout: Hashable, Sendable {
  public let tiling: Tiling
  /// The tiling area for each grid; the first includes the controller.
  public let areas: [Rect]
  public let controllerHeight: Double

  public init(tiling: Tiling, areas: [Rect], controllerHeight: Double) {
    self.tiling = tiling
    self.areas = areas
    self.controllerHeight = controllerHeight
  }

  public init(shape: GridShape, area: Rect, controllerHeight: Double) {
    self.init(tiling: Tiling(grids: [shape]), areas: [area], controllerHeight: controllerHeight)
  }

  /// The part of the `grid`th area that session windows are tiled into.
  public func sessionArea(ofGrid grid: Int) -> Rect {
    guard areas.indices.contains(grid) else { return zoomedFrame }
    var area = areas[grid]
    if grid == 0 { area.height -= controllerHeight }
    return area
  }

  public func frame(forWindowAt index: Int) -> Rect {
    guard let (grid, local) = tiling.locate(index), tiling.grids.indices.contains(grid) else {
      return zoomedFrame
    }
    let shape = tiling.grids[grid]
    let area = sessionArea(ofGrid: grid)
    let width = (area.width / Double(shape.columns)).rounded(.down)
    let height = (area.height / Double(shape.rows)).rounded(.down)
    let position = shape.position(of: local)
    return Rect(
      x: area.x + Double(position.column) * width,
      y: area.y + Double(position.row) * height,
      width: width,
      height: height
    )
  }

  private var controllerArea: Rect { areas.first ?? Rect(x: 0, y: 0, width: 0, height: 0) }

  public var controllerFrame: Rect {
    Rect(
      x: controllerArea.x, y: controllerArea.maxY - controllerHeight,
      width: controllerArea.width, height: controllerHeight)
  }

  /// The frame for a single window filling everything above the controller.
  public var zoomedFrame: Rect {
    Rect(
      x: controllerArea.x, y: controllerArea.y,
      width: controllerArea.width, height: controllerArea.height - controllerHeight)
  }
}
