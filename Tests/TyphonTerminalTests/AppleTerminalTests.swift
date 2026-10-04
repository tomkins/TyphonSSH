import Foundation
import Testing
import TyphonCore

@testable import TyphonTerminal

/// Records scripts instead of running them, replying with canned results.
@MainActor
final class RecordingRunner: AppleScriptRunner {
  var scripts: [String] = []
  var replies: [AppleScriptValue] = []

  func run(_ source: String) throws(AppleScriptError) -> AppleScriptValue {
    scripts.append(source)
    return replies.isEmpty ? .none : replies.removeFirst()
  }
}

@MainActor
@Suite struct AppleTerminalTests {
  let runner = RecordingRunner()
  var terminal: AppleTerminal { AppleTerminal(runner: runner, waitForModifierRelease: {}) }

  @Test func opensWindowsAndReturnsTheirIDs() throws {
    // `tab 1 of window id 4711`
    runner.replies = [
      .reference(
        form: .index, key: .integer(1),
        container: .reference(form: .id, key: .integer(4711), container: .none))
    ]
    #expect(try terminal.openWindow(running: #"clear && exec tyssh session --host "a""#) == 4711)
    #expect(runner.scripts[0].contains(#"do script "clear && exec tyssh session --host \"a\"""#))
  }

  @Test(arguments: [
    AppleScriptValue.none,
    .integer(4711),
    .reference(form: .index, key: .integer(1), container: .none),
  ])
  func throwsWhenNoWindowIsFound(reply: AppleScriptValue) {
    runner.replies = [reply]
    #expect(throws: TerminalError.unexpectedResult("a new window")) {
      try terminal.openWindow(running: "x")
    }
  }

  @Test func arrangesWindowsInOneScript() throws {
    try terminal.arrange([
      WindowPlacement(window: 1, frame: Rect(x: 0, y: 25, width: 400, height: 300)),
      WindowPlacement(window: 2, frame: Rect(x: 400, y: 25, width: 400, height: 300)),
    ])
    #expect(runner.scripts.count == 1)
    #expect(runner.scripts[0].contains("set bounds of w to {0, 25, 400, 325}"))
    #expect(runner.scripts[0].contains("set bounds of w to {400, 25, 800, 325}"))
  }

  @Test func skipsScriptsWithNothingToDo() throws {
    try terminal.arrange([])
    try terminal.hide([])
    try terminal.setColors([1: ColorPair()])
    #expect(try terminal.colors(of: []) == [:])
    try terminal.send(.splitPane, to: [], thenFocus: 9)
    #expect(runner.scripts.isEmpty)
  }

  @Test func readsFrames() throws {
    runner.replies = [.list([.integer(10), .integer(20), .integer(110), .integer(70)])]
    #expect(try terminal.frame(of: 1) == Rect(x: 10, y: 20, width: 100, height: 50))
  }

  @Test func readsAndWritesColorsInOneScript() throws {
    let white = AppleScriptValue.list([.integer(65535), .integer(65535), .integer(65535)])
    let black = AppleScriptValue.list([.integer(0), .integer(0), .integer(0)])
    // Window 4 has closed.
    runner.replies = [.list([.list([white, black]), .none])]
    #expect(
      try terminal.colors(of: [3, 4])
        == [3: ColorPair(foreground: .white, background: TerminalColor("#000000"))])

    try terminal.setColors([
      3: ColorPair(background: TerminalColor("{1,2,3}")),
      4: ColorPair(foreground: .white),
      5: ColorPair(),
    ])
    #expect(runner.scripts.count == 2)
    let script = runner.scripts[1]
    #expect(script.contains("set background color of t to {1, 2, 3}"))
    #expect(script.contains("set normal text color of t to {65535, 65535, 65535}"))
    #expect(!script.contains("window id 5"))
  }

  @Test func sendsShortcutsThenRefocuses() throws {
    try terminal.send(.closeSplitPane, to: [1, 2], thenFocus: 9)
    let script = runner.scripts[0]
    #expect(
      script.components(separatedBy: #"keystroke "d" using {command down, shift down}"#).count == 3)
    #expect(script.hasSuffix("set frontmost of window id 9 to true"))
  }

  @Test func notifiesThroughTerminal() {
    TerminalNotifier(runner: runner).notify("Closed web1")
    #expect(
      runner.scripts == [
        #"tell application "Terminal" to display notification "Closed web1" with title "tyssh""#
      ])
  }

  @Test(arguments: [
    TerminalScript.openWindow(running: "echo \"hi\" \\ there"),
    TerminalScript.windowID(forTTY: "/dev/ttys001"),
    TerminalScript.arrange([
      WindowPlacement(window: 1, frame: Rect(x: 0, y: 0, width: 10, height: 10))
    ]),
    TerminalScript.frame(of: 1),
    TerminalScript.setFrame(Rect(x: 0, y: 0, width: 10, height: 10), of: 1),
    TerminalScript.colors(of: [1, 2]),
    TerminalScript.setColors([1: ColorPair(foreground: .white, background: .white), 2: ColorPair()]
    ),
    TerminalScript.setProfile("Pro", of: 1),
    TerminalScript.set("visible", to: false, of: [1, 2]),
    TerminalScript.close([1]),
    TerminalScript.history(of: 1),
    TerminalScript.send(Keystroke(for: .biggerFont), to: [1], thenFocus: 2),
    TerminalNotifier.script(for: #"Closed "web1""#),
  ])
  func generatedScriptsCompile(source: String) throws {
    let script = try #require(NSAppleScript(source: source))
    var error: NSDictionary?
    let compiled = script.compileAndReturnError(&error)
    #expect(compiled, "\(error ?? [:])\n\(source)")
  }
}

@Suite struct AppleScriptValueTests {
  @Test func readsReferences() {
    // What Terminal's `do script` replies with: `tab 1 of window id 7801`.
    let window = specifier(
      form: formUniqueID, key: NSAppleEventDescriptor(int32: 7801), container: .null())
    let tab = specifier(
      form: formAbsolutePosition, key: NSAppleEventDescriptor(int32: 1), container: window)
    #expect(
      AppleScriptValue(tab)
        == .reference(
          form: .index, key: .integer(1),
          container: .reference(form: .id, key: .integer(7801), container: .none)))
  }

  private func specifier(form: Int, key: NSAppleEventDescriptor, container: NSAppleEventDescriptor)
    -> NSAppleEventDescriptor
  {
    let record = NSAppleEventDescriptor.record()
    record.setDescriptor(
      NSAppleEventDescriptor(enumCode: OSType(form)), forKeyword: AEKeyword(keyAEKeyForm))
    record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
    record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
    return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
  }
}

@Suite struct ScreenGeometryTests {
  @Test func flipsAppKitFramesToTopLeftOrigin() {
    // A 1440×900 main display with a 25pt menu bar and no Dock.
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    #expect(visible.flipped(mainScreenHeight: 900) == Rect(x: 0, y: 25, width: 1440, height: 875))
    // A display above the main one.
    let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
    #expect(above.flipped(mainScreenHeight: 900) == Rect(x: 0, y: -1080, width: 1920, height: 1080))
  }
}
