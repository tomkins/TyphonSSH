import Foundation
import Testing
import TyphonCore

@Suite struct TerminalColorTests {
  @Test(arguments: ["{17990,35209,53456}", "{ 17990, 35209, 53456 }"])
  func parsesAppleScriptTriples(input: String) {
    #expect(TerminalColor(input) == TerminalColor(red: 17990, green: 35209, blue: 53456))
  }

  @Test(arguments: ["FF8000", "#ff8000"])
  func parsesHex(input: String) {
    #expect(TerminalColor(input) == TerminalColor(red: 65535, green: 32896, blue: 0))
  }

  @Test(arguments: ["", "FFF", "#GGGGGG", "{1,2}", "{1,2,3,4}", "{70000,0,0}", "red"])
  func rejectsInvalid(input: String) {
    #expect(TerminalColor(input) == nil)
  }

  @Test func formatsForAppleScript() {
    #expect(TerminalColor.white.appleScriptLiteral == "{65535, 65535, 65535}")
  }

  @Test func roundTripsThroughJSON() throws {
    let pair = ColorPair(foreground: TerminalColor("#102030"))
    let data = try JSONEncoder().encode(pair)
    #expect(try JSONDecoder().decode(ColorPair.self, from: data) == pair)
  }
}

@Suite struct ControlKeyTests {
  @Test(arguments: [("ctrl-a", UInt8(0x01)), ("Ctrl-Z", 0x1A), ("^b", 0x02), ("ctrl-]", 0x1D)])
  func parses(input: String, byte: UInt8) {
    #expect(ControlKey(input)?.byte == byte)
  }

  @Test(arguments: ["a", "ctrl-", "ctrl-ab", "ctrl-[", "ctrl-1", "alt-a"])
  func rejectsInvalid(input: String) {
    #expect(ControlKey(input) == nil)
  }

  @Test func describesItself() {
    #expect(ControlKey.ctrlA.description == "Ctrl-A")
  }
}

@Suite struct ScreenSelectionTests {
  @Test func parses() {
    #expect(ScreenSelection("2") == .single(2))
    #expect(ScreenSelection("1-2") == .span(1, 2))
    #expect(ScreenSelection("0") == nil)
    #expect(ScreenSelection("1-2-3") == nil)
    #expect(ScreenSelection("one") == nil)
  }

  @Test func decodesNumbersAndStrings() throws {
    let decoded = try JSONDecoder().decode([ScreenSelection].self, from: Data(#"[2, "1-2"]"#.utf8))
    #expect(decoded == [.single(2), .span(1, 2)])
  }
}
