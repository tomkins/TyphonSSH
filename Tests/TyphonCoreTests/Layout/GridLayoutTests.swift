import Testing
import TyphonCore

@Suite struct GridTests {
  let area = Rect(x: 0, y: 25, width: 1200, height: 787)

  @Test(arguments: [
    (1, 1), (2, 2), (3, 3), (4, 2), (5, 3), (6, 3), (7, 4), (8, 4), (9, 3), (10, 5), (12, 4),
    (16, 4),
  ])
  func choosesColumnsAutomatically(count: Int, columns: Int) {
    #expect(GridShape.automaticColumns(for: count) == columns)
  }

  @Test func fixedColumnsWinOverRows() {
    let layout = GridShape(count: 6, columns: 2, rows: 1)
    #expect(layout.columns == 2)
    #expect(layout.rows == 3)
  }

  @Test func rowsDeriveColumns() {
    #expect(GridShape(count: 7, rows: 2).columns == 4)
  }

  @Test func columnsAreClampedToTheWindowCount() {
    #expect(GridShape(count: 2, columns: 5).columns == 2)
    #expect(GridShape(count: 0).columns == 1)
  }

  @Test func tilesRowByRowAboveTheController() {
    let layout = GridLayout(
      shape: GridShape(count: 5, columns: 3), area: area, controllerHeight: 87)
    #expect(layout.frame(forWindowAt: 0) == Rect(x: 0, y: 25, width: 400, height: 350))
    #expect(layout.frame(forWindowAt: 4) == Rect(x: 400, y: 375, width: 400, height: 350))
    #expect(layout.controllerFrame == Rect(x: 0, y: 725, width: 1200, height: 87))
    #expect(layout.zoomedFrame == Rect(x: 0, y: 25, width: 1200, height: 700))
  }

  @Test func mapsBetweenIndicesAndPositions() {
    let layout = GridShape(count: 5, columns: 3)
    #expect(layout.position(of: 4) == GridPosition(column: 1, row: 1))
    #expect(layout.index(at: GridPosition(column: 1, row: 1)) == 4)
    #expect(layout.index(at: GridPosition(column: 2, row: 1)) == nil)
    #expect(layout.index(at: GridPosition(column: 3, row: 0)) == nil)
  }

  /// 0 1 2
  /// 3 4 ·
  @Test func movesWithWrappingAndSkipsEmptyCells() {
    let layout = GridShape(count: 5, columns: 3)
    #expect(layout.index(movingFrom: 0, .right) == 1)
    #expect(layout.index(movingFrom: 0, .left) == 2)
    #expect(layout.index(movingFrom: 4, .right) == 3)
    #expect(layout.index(movingFrom: 3, .left) == 4)
    #expect(layout.index(movingFrom: 1, .down) == 4)
    #expect(layout.index(movingFrom: 2, .down) == 2)
    #expect(layout.index(movingFrom: 2, .up) == 2)
    #expect(layout.index(movingFrom: 0, .up) == 3)
  }
}

/// Two screens: grid 0 has sessions 0-2, grid 1 has sessions 3-7.
///
/// 0 1    3 4 5
/// 2 ·    6 7 ·
@Suite struct TilingTests {
  let tiling = Tiling(grids: [GridShape(count: 3, columns: 2), GridShape(count: 5, columns: 3)])

  @Test func sharesWindowsInProportion() {
    #expect(Tiling.share(8, by: [1, 1]) == [4, 4])
    #expect(Tiling.share(7, by: [1, 1]) == [4, 3])
    #expect(Tiling.share(10, by: [1, 2, 2]) == [2, 4, 4])
    #expect(Tiling.share(2, by: [1, 1, 1]) == [1, 1, 0])
    #expect(Tiling.share(3, by: [0, 0]) == [3, 0])
    #expect(Tiling.share(3, by: []) == [3])
  }

  @Test func locatesWindows() {
    #expect(tiling.count == 8)
    #expect(tiling.locate(2)! == (grid: 0, index: 2))
    #expect(tiling.locate(3)! == (grid: 1, index: 0))
    #expect(tiling.locate(8) == nil)
  }

  @Test func movesAcrossGrids() {
    #expect(tiling.index(movingFrom: 1, .right) == 3)
    #expect(tiling.index(movingFrom: 2, .right) == 6)
    #expect(tiling.index(movingFrom: 3, .left) == 1)
    #expect(tiling.index(movingFrom: 6, .left) == 2)
    #expect(tiling.index(movingFrom: 5, .right) == 0)
    #expect(tiling.index(movingFrom: 7, .right) == 2)
    #expect(tiling.index(movingFrom: 0, .left) == 5)
    #expect(tiling.index(movingFrom: 1, .down) == 1)
    #expect(tiling.index(movingFrom: 4, .down) == 7)
  }

  @Test func skipsEmptyGrids() {
    let tiling = Tiling(grids: [GridShape(count: 2), GridShape(count: 0), GridShape(count: 1)])
    #expect(tiling.index(movingFrom: 1, .right) == 2)
    #expect(tiling.index(movingFrom: 2, .right) == 0)
  }

  @Test func layOutEachGridInItsOwnArea() {
    let layout = GridLayout(
      tiling: tiling,
      areas: [
        Rect(x: 0, y: 25, width: 1200, height: 787),
        Rect(x: 1200, y: -200, width: 1800, height: 1000),
      ],
      controllerHeight: 87)
    #expect(layout.frame(forWindowAt: 2) == Rect(x: 0, y: 375, width: 600, height: 350))
    #expect(layout.frame(forWindowAt: 3) == Rect(x: 1200, y: -200, width: 600, height: 500))
    #expect(layout.frame(forWindowAt: 7) == Rect(x: 1800, y: 300, width: 600, height: 500))
    #expect(layout.controllerFrame == Rect(x: 0, y: 725, width: 1200, height: 87))
    #expect(layout.zoomedFrame == Rect(x: 0, y: 25, width: 1200, height: 700))
  }
}

@Suite struct RectTests {
  @Test func movesAndResizes() {
    let rect = Rect(x: 10, y: 20, width: 100, height: 50)
    #expect(rect.offsetBy(dx: 5, dy: -5) == Rect(x: 15, y: 15, width: 100, height: 50))
    #expect(rect.resizedBy(dWidth: -200, dHeight: 10) == Rect(x: 10, y: 20, width: 1, height: 60))
  }
}

@Suite struct TilingAreaTests {
  let screens = [
    Rect(x: 0, y: 25, width: 1440, height: 875),
    Rect(x: 1440, y: 0, width: 1920, height: 1055),
    Rect(x: 0, y: -1080, width: 1920, height: 1080),
  ]

  @Test func usesTheSelectedScreens() throws {
    #expect(try TilingArea.resolve(.single(2), screens: screens) == [screens[1]])
    #expect(
      try TilingArea.resolve(.screens([3, 1]), screens: screens) == [screens[2], screens[0]])
    #expect(try TilingArea.resolve(.all, screens: screens) == screens)
  }

  @Test func rejectsMissingScreens() {
    #expect(throws: TilingAreaError.noSuchScreen(4, available: 3)) {
      try TilingArea.resolve(.screens([1, 4]), screens: screens)
    }
    #expect(throws: TilingAreaError.noSuchScreen(1, available: 0)) {
      try TilingArea.resolve(.all, screens: [])
    }
  }

  @Test func prefersConfiguredBounds() throws {
    var configuration = Configuration()
    configuration.screen = .all
    configuration.screenBounds = Rect(x: 10, y: 10, width: 100, height: 100)
    #expect(
      try TilingArea.resolve(for: configuration, screens: screens) == [configuration.screenBounds!])
  }
}
