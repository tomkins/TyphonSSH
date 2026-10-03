import Testing
import TyphonCore

@Suite struct SessionAppearanceTests {
  let original = ColorPair(
    foreground: TerminalColor("#000000"), background: TerminalColor("#FFFFFF"))
  var scheme: ColorScheme {
    var scheme = ColorScheme()
    scheme.selected = ColorPair(background: TerminalColor("#0000FF"))
    scheme.disabled = ColorPair(
      foreground: TerminalColor("#888888"), background: TerminalColor("#333333"))
    return scheme
  }

  @Test func normalWindowsKeepTheirColors() {
    #expect(SessionAppearance().colors(scheme: scheme, original: original) == original)
  }

  @Test func disabledWindowsUseDisabledColors() {
    #expect(
      SessionAppearance(isEnabled: false).colors(scheme: scheme, original: original)
        == ColorPair(foreground: TerminalColor("#888888"), background: TerminalColor("#333333")))
  }

  @Test func selectionWinsTheBackgroundAndDisabledWinsTheForeground() {
    #expect(
      SessionAppearance(isEnabled: false, isSelected: true).colors(
        scheme: scheme, original: original)
        == ColorPair(foreground: TerminalColor("#888888"), background: TerminalColor("#0000FF")))
  }

  @Test func absentSchemeColorsFallBackToOriginal() {
    #expect(
      SessionAppearance(isSelected: true).colors(scheme: scheme, original: original)
        == ColorPair(foreground: TerminalColor("#000000"), background: TerminalColor("#0000FF")))
  }
}

@Suite struct LineEditorTests {
  func type(_ keys: [Key]) -> (LineEditor, LineEditor.Outcome) {
    var editor = LineEditor()
    var outcome = LineEditor.Outcome.editing
    for key in keys { outcome = editor.handle(key) }
    return (editor, outcome)
  }

  @Test func editsAndSubmits() {
    let keys = KeyDecoder.keys(in: Array("web1 xx\u{7F}\u{7F}db\u{17}cache\r".utf8))
    #expect(type(keys).1 == .submitted("web1 cache"))
  }

  @Test func clearsLine() {
    #expect(type([.character("a"), .control(0x15), .character("b")]).0.text == "b")
  }

  @Test func cancels() {
    #expect(type([.character("a"), .escape]).1 == .cancelled)
  }
}

@Suite struct ScrollbackFilesTests {
  @Test func namesFilesUniquelyAndSafely() {
    let sessions = [
      Session(id: SessionID(1), host: HostSpec(user: "username", hostname: "web1", port: 22)),
      Session(id: SessionID(2), host: HostSpec(hostname: "web1")),
      Session(id: SessionID(3), host: HostSpec(hostname: "web1")),
      Session(id: SessionID(4), host: HostSpec(hostname: "web 1/x")),
    ]
    let paths = ScrollbackFiles.paths(for: sessions, baseName: "dump").map(\.1)
    #expect(
      paths == [
        "dump.username@web1_22.txt", "dump.web1.txt", "dump.web1.1.txt", "dump.web_1_x.txt",
      ])
  }
}

@Suite struct SessionRosterTests {
  @Test func ordersByIdOrHostname() {
    var roster = SessionRoster()
    let b = roster.add(HostSpec(hostname: "b"))
    let a = roster.add(HostSpec(hostname: "a"))
    #expect(roster.ordered.map(\.id) == [b, a])
    roster.order = .hostname
    #expect(roster.ordered.map(\.id) == [a, b])
  }

  @Test func assignsIdsAfterTheHighestInUse() {
    var roster = SessionRoster()
    _ = roster.add(HostSpec(hostname: "a"))
    let second = roster.add(HostSpec(hostname: "b"))
    roster.remove(second)
    #expect(roster.add(HostSpec(hostname: "c")) == SessionID(2))
  }
}
