import Foundation
import System
import Testing
import TyphonCore

@testable import TyphonTerminal

@MainActor
final class FakeTerminal: TerminalApp {
  enum Call: Equatable {
    case open(String)
    case arrange([WindowPlacement])
    case setFrame(Rect, TerminalWindowID)
    case setColors(ColorPair, TerminalWindowID)
    case setProfile(String, TerminalWindowID)
    case hide([TerminalWindowID])
    case minimize([TerminalWindowID])
    case close([TerminalWindowID])
    case send(TerminalShortcut, [TerminalWindowID], TerminalWindowID?)
  }

  var calls: [Call] = []
  var nextWindow = 100
  var frames: [TerminalWindowID: Rect] = [:]
  var failOpening = false
  /// Mimics Terminal refusing to make windows shorter than this.
  var minimumHeight: Double = 0
  let controllerWindow = 1
  let original = ColorPair(
    foreground: TerminalColor("#000000"), background: TerminalColor("#FFFFFF"))

  func openWindow(running command: String) throws -> TerminalWindowID {
    if failOpening { throw AppleScriptError(number: -1743, message: "Not authorised") }
    calls.append(.open(command))
    nextWindow += 1
    return nextWindow
  }

  func windowID(forTTY tty: String) throws -> TerminalWindowID? {
    tty == "/dev/ttys000" ? controllerWindow : nil
  }

  func arrange(_ placements: [WindowPlacement]) throws {
    calls.append(.arrange(placements))
    for placement in placements {
      var frame = placement.frame
      frame.height = max(frame.height, minimumHeight)
      frames[placement.window] = frame
    }
  }

  func frame(of window: TerminalWindowID) throws -> Rect {
    frames[window] ?? Rect(x: 0, y: 0, width: 100, height: 100)
  }

  func setFrame(_ frame: Rect, of window: TerminalWindowID) throws {
    calls.append(.setFrame(frame, window))
    var frame = frame
    frame.height = max(frame.height, minimumHeight)
    frames[window] = frame
  }

  func colors(of window: TerminalWindowID) throws -> ColorPair { original }
  func setColors(_ colors: ColorPair, of window: TerminalWindowID) throws {
    calls.append(.setColors(colors, window))
  }
  func setProfile(_ name: String, of window: TerminalWindowID) throws {
    calls.append(.setProfile(name, window))
  }
  func hide(_ windows: [TerminalWindowID]) throws { calls.append(.hide(windows)) }
  func minimize(_ windows: [TerminalWindowID]) throws { calls.append(.minimize(windows)) }
  func close(_ windows: [TerminalWindowID]) throws { calls.append(.close(windows)) }
  func history(of window: TerminalWindowID) throws -> String { "history of \(window)\n" }

  func send(
    _ shortcut: TerminalShortcut, to windows: [TerminalWindowID], thenFocus focus: TerminalWindowID?
  ) throws {
    calls.append(.send(shortcut, windows, focus))
  }
}

struct FixedScreens: ScreenProvider {
  func visibleFrames() -> [Rect] { [Rect(x: 0, y: 25, width: 1200, height: 787)] }
}

@MainActor
final class RecordingNotifier: Notifier {
  var messages: [String] = []
  func notify(_ message: String) { messages.append(message) }
}

@MainActor
@Suite struct ControllerRuntimeTests {
  let terminal = FakeTerminal()
  let notifier = RecordingNotifier()
  let home = FileManager.default.temporaryDirectory.appending(
    path: "tyssh-home-\(UUID().uuidString.prefix(8))")

  func makeRuntime(
    hosts: [String] = ["web1", "web2"], configure: (inout Configuration) -> Void = { _ in }
  ) -> ControllerRuntime {
    var configuration = Configuration()
    configuration.sessionProfile = "Quiet"
    configure(&configuration)
    let plan = SessionPlan(
      configuration: configuration, hosts: hosts.map { HostSpec(hostname: $0) },
      socketPath: "/tmp/t.sock")
    var tokens = 0
    let environment = ControllerRuntime.Environment(
      terminal: terminal,
      screens: FixedScreens(),
      notifier: notifier,
      output: TerminalOutput(FileDescriptor(rawValue: open("/dev/null", O_WRONLY))),
      commands: WindowCommands(executable: "/bin/tyssh"),
      homeDirectory: home,
      tty: "/dev/ttys000",
      makeToken: {
        tokens += 1
        return "token\(tokens)"
      }
    )
    return ControllerRuntime(plan: plan, environment: environment)
  }

  @Test func startStylesTheControllerOpensSessionsAndTiles() throws {
    let runtime = makeRuntime()
    runtime.start()

    let scheme = Configuration().colors.controller
    #expect(
      terminal.calls == [
        .setColors(scheme, terminal.controllerWindow),
        .setFrame(Rect(x: 0, y: 725, width: 1200, height: 87), terminal.controllerWindow),
        .open(
          " exec /bin/tyssh _session --socket /tmp/t.sock --id 1 --token token1 --title web1 -- ssh -- web1"
        ),
        .setProfile("Quiet", 101),
        .open(
          " exec /bin/tyssh _session --socket /tmp/t.sock --id 2 --token token2 --title web2 -- ssh -- web2"
        ),
        .setProfile("Quiet", 102),
        .arrange([
          WindowPlacement(window: 101, frame: Rect(x: 0, y: 25, width: 600, height: 700)),
          WindowPlacement(window: 102, frame: Rect(x: 600, y: 25, width: 600, height: 700)),
          WindowPlacement(window: 1, frame: Rect(x: 0, y: 725, width: 1200, height: 87)),
        ]),
      ])
  }

  @Test func makesRoomForAControllerTallerThanConfigured() throws {
    terminal.minimumHeight = 120
    let runtime = makeRuntime()
    runtime.start()

    // Measured before the sessions open, so they're tiled only once.
    let arrangements = terminal.calls.filter { if case .arrange = $0 { true } else { false } }
    #expect(
      arrangements
        == [
          .arrange([
            WindowPlacement(window: 101, frame: Rect(x: 0, y: 25, width: 600, height: 667)),
            WindowPlacement(window: 102, frame: Rect(x: 600, y: 25, width: 600, height: 667)),
            WindowPlacement(window: 1, frame: Rect(x: 0, y: 692, width: 1200, height: 120)),
          ])
        ])

    // The real height is remembered, so later retiles need only one pass.
    terminal.calls = []
    runtime.handleInput(Data("\u{01}r".utf8))
    #expect(terminal.calls.count == 1)
  }

  @Test func recoloursWindowsFromTheirOriginalColours() throws {
    let runtime = makeRuntime()
    runtime.start()
    terminal.calls = []

    runtime.handleInput(Data("\u{01}e".utf8))  // select web1
    runtime.handleInput(Data("\u{1B}".utf8))  // and back
    let selected = SessionAppearance(isSelected: true).colors(
      scheme: Configuration().colors, original: terminal.original)
    #expect(terminal.calls == [.setColors(selected, 101), .setColors(terminal.original, 101)])
  }

  @Test func zoomsAboveTheController() throws {
    let runtime = makeRuntime()
    runtime.start()
    terminal.calls = []

    runtime.handleInput(Data("\u{01}elO".utf8))
    #expect(
      terminal.calls.contains(
        .arrange([
          WindowPlacement(window: 102, frame: Rect(x: 0, y: 25, width: 1200, height: 700)),
          WindowPlacement(window: 1, frame: Rect(x: 0, y: 725, width: 1200, height: 87)),
        ])))
    #expect(notifier.messages == ["Zoomed web2"])
  }

  @Test func editsTheTilingAreaWithTheController() throws {
    let runtime = makeRuntime()
    runtime.start()
    terminal.calls = []

    runtime.handleInput(Data("\u{01}b".utf8))
    #expect(
      terminal.calls == [
        .hide([101, 102]),
        .setColors(Configuration().colors.bounds, 1),
        .arrange([WindowPlacement(window: 1, frame: Rect(x: 0, y: 25, width: 1200, height: 787))]),
      ])

    runtime.handleInput(Data("j\u{1B}[1;5D\r".utf8))  // down, narrower, accept
    #expect(runtime.tilingArea == Rect(x: 0, y: 35, width: 1190, height: 787))
    #expect(
      terminal.calls.last
        == .arrange([
          WindowPlacement(window: 101, frame: Rect(x: 0, y: 35, width: 595, height: 700)),
          WindowPlacement(window: 102, frame: Rect(x: 595, y: 35, width: 595, height: 700)),
          WindowPlacement(window: 1, frame: Rect(x: 0, y: 735, width: 1190, height: 87)),
        ]))
  }

  @Test func sendsShortcutsAndRefocusesTheController() {
    let runtime = makeRuntime()
    runtime.start()
    runtime.handleInput(Data("\u{01}f".utf8))
    #expect(terminal.calls.last == .send(.smallerFont, [101, 102, 1], 1))
  }

  @Test func dumpsScrollbackUnderTheHomeDirectory() throws {
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let runtime = makeRuntime()
    runtime.start()

    runtime.handleInput(Data("\u{01}dscroll\r".utf8))
    #expect(
      try String(contentsOf: home.appending(path: "scroll.web2.txt"), encoding: .utf8)
        == "history of 102\n")
    let attributes = try FileManager.default.attributesOfItem(
      atPath: home.appending(path: "scroll.web2.txt").path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
    #expect(runtime.state.prompt.last == "Saved 2 scrollback files, e.g. ~/scroll.web1.txt")
  }

  @Test func staysOpenToShowWhyWindowsCouldNotOpen() {
    terminal.failOpening = true
    let runtime = makeRuntime()
    runtime.start()
    #expect(runtime.state.roster.isEmpty)
    #expect(runtime.state.prompt.last?.contains("Privacy & Security") == true)
  }

  @Test func acceptsEachSessionOnceWithItsOwnToken() {
    let runtime = makeRuntime()
    runtime.start()
    func connect(_ id: Int, token: String) -> Bool {
      let connection = MessageConnection(
        descriptor: FileDescriptor(rawValue: open("/dev/null", O_RDWR)))
      return runtime.sessionConnected(
        SessionID(id), tty: "/dev/ttys001", token: token, connection: connection)
    }

    #expect(!connect(1, token: "wrong"))
    #expect(!connect(1, token: "token2"))
    #expect(connect(1, token: "token1"))
    #expect(!connect(1, token: "token1"))
    #expect(!connect(3, token: "token1"))
  }

  @Test func closesWindowsOfSessionsThatExitCleanly() async throws {
    let runtime = makeRuntime(hosts: ["web1", "web2", "web3"])
    runtime.start()
    terminal.calls = []

    runtime.sessionDisconnected(SessionID(1), exitCode: 255)
    runtime.sessionDisconnected(SessionID(2), exitCode: 0)
    try await Task.sleep(for: .milliseconds(500))
    #expect(terminal.calls.contains(.close([102])))
    #expect(!terminal.calls.contains(.close([101])))
    #expect(notifier.messages == ["Closed web1", "Closed web2"])
  }

  @Test func notifiesOnlyWhenEnabled() {
    let runtime = makeRuntime { $0.notifications = false }
    runtime.start()
    runtime.sessionDisconnected(SessionID(1))
    #expect(notifier.messages.isEmpty)
    #expect(runtime.state.roster.count == 1)
  }
}
