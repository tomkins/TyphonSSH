import Testing
import TyphonCore

@Suite struct KeyDecoderTests {
  func keys(_ string: String) -> [Key] {
    KeyDecoder.keys(in: Array(string.utf8))
  }

  @Test func decodesPrintablesAndControls() {
    #expect(
      keys("a Z\r\u{01}\u{7F}\u{08}") == [
        .character("a"), .character(" "), .character("Z"), .enter, .control(0x01), .backspace,
        .control(0x08),
      ])
  }

  @Test func decodesArrowKeys() {
    #expect(
      keys("\u{1B}[A\u{1B}[B\u{1B}OC\u{1B}OD") == [
        .arrow(.up, modified: false), .arrow(.down, modified: false),
        .arrow(.right, modified: false), .arrow(.left, modified: false),
      ])
  }

  @Test func decodesModifiedArrows() {
    #expect(
      keys("\u{1B}[5C\u{1B}[1;5D") == [
        .arrow(.right, modified: true), .arrow(.left, modified: true),
      ])
  }

  @Test func decodesEscape() {
    #expect(keys("\u{1B}") == [.escape])
    #expect(keys("\u{1B}x") == [.escape, .character("x")])
    #expect(keys("\u{1B}[") == [.escape, .character("[")])
  }

  @Test func keepsUnknownSequences() {
    #expect(keys("\u{1B}[3~") == [.unknown(Array("\u{1B}[3~".utf8))])
  }

  @Test func decodesUTF8() {
    #expect(keys("é🙂") == [.character("é"), .character("🙂")])
    #expect(KeyDecoder.keys(in: [0xC3]) == [.unknown([0xC3])])
  }

  @Test func rewritesCursorKeysForApplicationMode() {
    let input = Array("ls\u{1B}[A\u{1B}[3~\u{1B}[".utf8)
    #expect(KeyDecoder.applicationCursorKeys(input) == Array("ls\u{1B}OA\u{1B}[3~\u{1B}[".utf8))
  }
}
