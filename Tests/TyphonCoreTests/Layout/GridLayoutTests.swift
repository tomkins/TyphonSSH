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

@Suite struct RectTests {
  @Test func spansSideBySideDisplays() {
    let left = Rect(x: 0, y: 25, width: 1440, height: 875)
    let right = Rect(x: 1440, y: 0, width: 1920, height: 1055)
    #expect(Rect.spanning(left, right) == Rect(x: 0, y: 25, width: 3360, height: 875))
    #expect(Rect.spanning(right, left) == Rect(x: 0, y: 25, width: 3360, height: 875))
  }

  @Test func spansStackedDisplays() {
    let top = Rect(x: 0, y: -1080, width: 1920, height: 1080)
    let bottom = Rect(x: 240, y: 25, width: 1440, height: 875)
    #expect(Rect.spanning(top, bottom) == Rect(x: 240, y: -1080, width: 1440, height: 1980))
  }

  @Test func movesAndResizes() {
    let rect = Rect(x: 10, y: 20, width: 100, height: 50)
    #expect(rect.offsetBy(dx: 5, dy: -5) == Rect(x: 15, y: 15, width: 100, height: 50))
    #expect(rect.resizedBy(dWidth: -200, dHeight: 10) == Rect(x: 10, y: 20, width: 1, height: 60))
  }
}
