import Foundation
import Testing

@testable import TyphonCore

/// Drives a `ControllerState` with keystrokes, as a user at the controller would.
struct Harness {
  var state: ControllerState
  let ids: [SessionID]

  init(
    hosts: [String] = ["web1", "web2", "web3", "db1", "db2"],
    configure: (inout Configuration) -> Void = { _ in }
  ) {
    var configuration = Configuration()
    configuration.clusters = ["cache": ["cache1", "cache2"]]
    configure(&configuration)
    state = ControllerState(
      configuration: configuration,
      hostResolver: HostListResolver(configuration: configuration, resolver: StubResolver())
    )
    let effects = state.open(hosts.map { HostSpec(hostname: $0) })
    ids = effects.compactMap {
      if case .openSession(let id, _) = $0 { id } else { nil }
    }
    for id in ids { state.attach(windowID: 1000 + id.rawValue, to: id) }
  }

  @discardableResult
  mutating func type(_ text: String) -> [ControllerEffect] {
    state.handle(Array(text.utf8))
  }

  var enabled: [String] { state.roster.enabled.map(\.host.hostname) }
}

let ctrlA = "\u{01}"
let esc = "\u{1B}"

@Suite struct ControllerLifecycleTests {
  @Test func openingHostsOpensWindowsThenTiles() {
    var state = ControllerState(configuration: Configuration())
    let effects = state.open([HostSpec(hostname: "a"), HostSpec(hostname: "b")])
    #expect(
      effects == [
        .openSession(SessionID(1), HostSpec(hostname: "a")),
        .openSession(SessionID(2), HostSpec(hostname: "b")),
        .retile,
      ])
  }

  @Test func closingASessionRetilesAndNotifies() {
    var harness = Harness(hosts: ["a", "b"])
    #expect(harness.state.sessionDidClose(harness.ids[0]) == [.notify("Closed a"), .retile])
    #expect(harness.state.sessionDidClose(harness.ids[0]) == [])
  }

  @Test func closingTheLastSessionQuits() {
    var harness = Harness(hosts: ["a"])
    #expect(harness.state.sessionDidClose(harness.ids[0]) == [.quit])
  }
}

@Suite struct ControllerInputModeTests {
  @Test func broadcastsToEnabledSessions() {
    var harness = Harness(hosts: ["a", "b"])
    #expect(harness.type("ls\r") == [.send(Data("ls\r".utf8), to: harness.ids)])
  }

  @Test func convertsCursorKeysToApplicationMode() {
    var harness = Harness(hosts: ["a"])
    #expect(harness.type("\(esc)[A") == [.send(Data("\(esc)OA".utf8), to: harness.ids)])
  }

  @Test func actionKeySplitsInputAndEntersActionMode() {
    var harness = Harness(hosts: ["a"])
    #expect(harness.type("abc\(ctrlA)") == [.send(Data("abc".utf8), to: harness.ids)])
    #expect(harness.state.mode == .action)
  }

  @Test func remainingBytesAreInterpretedInTheNewMode() {
    var harness = Harness(hosts: ["a"])
    // Ctrl-A, Esc back to input, then more input, all in one read.
    #expect(
      harness.type("x\(ctrlA)\(esc)y") == [
        .send(Data("x".utf8), to: harness.ids),
        .send(Data("y".utf8), to: harness.ids),
      ])
    #expect(harness.state.mode == .input)
  }

  @Test func doubleActionKeySendsTheActionKey() {
    var harness = Harness(hosts: ["a"])
    #expect(harness.type("\(ctrlA)\(ctrlA)") == [.send(Data([0x01]), to: harness.ids)])
    #expect(harness.state.mode == .input)
  }

  @Test func honoursAConfiguredActionKey() {
    var harness = Harness(hosts: ["a"]) { $0.actionKey = ControlKey("ctrl-b")! }
    #expect(harness.type("\(ctrlA)") == [.send(Data([0x01]), to: harness.ids)])
    harness.type("\u{02}")
    #expect(harness.state.mode == .action)
    #expect(harness.state.prompt[0].contains("Ctrl-B"))
  }
}

@Suite struct ControllerActionModeTests {
  @Test func retiles() {
    var harness = Harness()
    #expect(harness.type("\(ctrlA)r") == [.retile])
    #expect(harness.state.mode == .input)
  }

  @Test func unknownKeysRing() {
    var harness = Harness()
    #expect(harness.type("\(ctrlA)Q") == [.bell])
    #expect(harness.state.mode == .action)
  }

  @Test func growsAndShrinksTheGrid() {
    var harness = Harness()  // 5 sessions: 3 columns automatically
    #expect(harness.state.shape.columns == 3)
    #expect(harness.type("\(ctrlA)g") == [.retile])
    #expect(harness.state.shape.columns == 4)
    harness.type("ggg")
    #expect(harness.state.shape.columns == 5)
    harness.type("GGGGGGG")
    #expect(harness.state.shape.columns == 1)
    #expect(harness.state.mode == .action)
  }

  @Test func togglesAndReenablesAll() {
    var harness = Harness(hosts: ["a", "b"])
    let effects = harness.type("\(ctrlA)t")
    #expect(harness.enabled.isEmpty)
    let disabled = harness.ids.map { ($0, SessionAppearance(isEnabled: false)) }
    #expect(effects == [.setAppearances(Dictionary(uniqueKeysWithValues: disabled))])
    harness.type("\(ctrlA)n")
    #expect(harness.enabled == ["a", "b"])
  }

  @Test func sendsShortcuts() {
    var harness = Harness(hosts: ["a"])
    #expect(
      harness.type("\(ctrlA)f") == [
        .shortcut(.smallerFont, sessions: harness.ids, includingController: true)
      ])
    #expect(
      harness.type("F") == [
        .shortcut(.biggerFont, sessions: harness.ids, includingController: true)
      ])
    #expect(
      harness.type("p") == [
        .shortcut(.splitPane, sessions: harness.ids, includingController: false), .retile,
      ])
  }

  @Test func hidesMinimisesAndQuits() {
    var harness = Harness()
    #expect(harness.type("\(ctrlA)h") == [.hideSessions])
    #expect(harness.type("\(ctrlA)m") == [.hideSessions, .minimizeController])
    #expect(harness.type("\(ctrlA)\u{08}") == [.hideSessions, .minimizeController])
    #expect(harness.type("\(ctrlA)x") == [.quit])
  }

  @Test func spaceMovesInputToTheNextSession() {
    var harness = Harness(hosts: ["a", "b", "c"])
    #expect(harness.type("\(ctrlA) ") == [.bell])  // Only works when exactly one is enabled.

    harness.type("\(ctrlA)e")  // select a
    harness.type("o")  // only a enabled
    #expect(harness.enabled == ["a"])
    #expect(harness.state.prompt.joined().contains("enable next") == false)
    harness.type("\(ctrlA)")
    #expect(harness.state.prompt.joined().contains("[Space] enable next"))

    let effects = harness.type(" ")
    #expect(harness.enabled == ["b"])
    #expect(effects.contains(.notify("Enabled next b")))
    harness.type("\(ctrlA) \(ctrlA) ")
    #expect(harness.enabled == ["a"])
  }
}

@Suite struct ControllerSelectModeTests {
  /// Grid for 5 sessions:
  ///   web1 web2 web3
  ///   db1  db2
  @Test func movesTheSelectionAroundTheGrid() {
    var harness = Harness()
    let enter = harness.type("\(ctrlA)e")
    #expect(enter == [.setAppearances([harness.ids[0]: SessionAppearance(isSelected: true)])])

    let moved = harness.type("\(esc)[B")
    #expect(
      moved == [
        .setAppearances([
          harness.ids[0]: SessionAppearance(),
          harness.ids[3]: SessionAppearance(isSelected: true),
        ])
      ])
    harness.type("ll")  // db1 → db2 → wraps to db1, skipping the empty cell
    #expect(harness.state.mode == .select(index: 3))
    harness.type("k\(esc)[D")  // up to web1, left wraps to web3
    #expect(harness.state.mode == .select(index: 2))
  }

  @Test func enablesAndDisablesTheSelectedSession() {
    var harness = Harness(hosts: ["a", "b"])
    harness.type("\(ctrlA)el")
    harness.type("d")
    #expect(harness.enabled == ["a"])
    harness.type("t")
    #expect(harness.enabled == ["a", "b"])
    harness.type("hd\r")
    #expect(harness.enabled == ["b"])
    #expect(harness.state.mode == .input)
    #expect(harness.state.appearances.values.allSatisfy { !$0.isSelected })
  }

  @Test func zoomsTheSelectedSessionAndUnzoomsOnRetile() {
    var harness = Harness(hosts: ["a", "b"])
    let effects = harness.type("\(ctrlA)elO")
    #expect(effects.contains(.zoom(harness.ids[1])))
    #expect(effects.contains(.notify("Zoomed b")))
    #expect(harness.enabled == ["b"])
    #expect(harness.state.zoomedSession == harness.ids[1])

    // Entering selection mode again un-zooms first.
    #expect(harness.type("\(ctrlA)e").first == .retile)
    #expect(harness.state.zoomedSession == nil)
  }

  @Test func zoomFollowsEnableNext() {
    var harness = Harness(hosts: ["a", "b"])
    harness.type("\(ctrlA)eO")
    let effects = harness.type("\(ctrlA) ")
    #expect(effects.contains(.zoom(harness.ids[1])))
    #expect(harness.state.zoomedSession == harness.ids[1])
  }
}

@Suite struct ControllerOtherModeTests {
  @Test func sendsPerSessionText() {
    var harness = Harness(hosts: ["a", "b"])
    harness.state = {
      var state = harness.state
      _ = state.handle(Array("\(ctrlA)el".utf8))
      _ = state.handle(Array("d\r".utf8))  // disable b
      return state
    }()
    #expect(harness.type("\(ctrlA)sh") == [.send(Data("a".utf8), to: [harness.ids[0]])])
    harness.type("\(ctrlA)n")
    #expect(
      harness.type("\(ctrlA)si") == [
        .send(Data("1001".utf8), to: [harness.ids[0]]),
        .send(Data("1002".utf8), to: [harness.ids[1]]),
      ])
    #expect(
      harness.type("\(ctrlA)ss") == [
        .send(Data("1".utf8), to: [harness.ids[0]]),
        .send(Data("2".utf8), to: [harness.ids[1]]),
      ])
  }

  @Test func sendsConnectionStrings() {
    var state = ControllerState(configuration: Configuration())
    _ = state.open([HostSpec(user: "username", hostname: "a", port: 2222)])
    #expect(
      state.handle(Array("\(ctrlA)sc".utf8)) == [
        .send(Data("username@a:2222".utf8), to: [SessionID(1)])
      ])
  }

  @Test func sortsByHostname() {
    var harness = Harness(hosts: ["b", "a"])
    #expect(harness.type("\(ctrlA)oh") == [.retile])
    #expect(harness.state.roster.ordered.map(\.host.hostname) == ["a", "b"])
    harness.type("\(ctrlA)oi")
    #expect(harness.state.roster.ordered.map(\.host.hostname) == ["b", "a"])
  }

  @Test func addsHostsIncludingClustersAndPatterns() {
    var harness = Harness(hosts: ["a"])
    harness.type("\(ctrlA)c")
    #expect(harness.type("cache web[1-2]") == [])
    #expect(harness.state.prompt[0].hasSuffix("cache web[1-2]"))
    let effects = harness.type("\r")
    #expect(
      effects == [
        .openSession(SessionID(2), HostSpec(hostname: "cache1")),
        .openSession(SessionID(3), HostSpec(hostname: "cache2")),
        .openSession(SessionID(4), HostSpec(hostname: "web1")),
        .openSession(SessionID(5), HostSpec(hostname: "web2")),
        .retile,
      ])
    #expect(harness.state.mode == .input)
  }

  @Test func reportsBadHostsInTheStatusLine() {
    var harness = Harness(hosts: ["a"])
    #expect(harness.type("\(ctrlA)cweb:x\r") == [.bell])
    #expect(harness.state.prompt.last == "Invalid port in host [web:x]")
    harness.type("z")
    #expect(harness.state.prompt.count == 1)
  }

  @Test func cancelsAddingHosts() {
    var harness = Harness(hosts: ["a"])
    #expect(harness.type("\(ctrlA)cweb9\(esc)") == [])
    #expect(harness.state.mode == .input)
  }

  @Test func dumpsScrollback() {
    var harness = Harness(hosts: ["a", "b"])
    #expect(
      harness.type("\(ctrlA)d\r") == [
        .dumpScrollback([
          ScrollbackDump(session: harness.ids[0], path: "Desktop/tyssh_scrollback.a.txt"),
          ScrollbackDump(session: harness.ids[1], path: "Desktop/tyssh_scrollback.b.txt"),
        ])
      ])
    #expect(
      harness.type("\(ctrlA)dlogs/run\r") == [
        .dumpScrollback([
          ScrollbackDump(session: harness.ids[0], path: "logs/run.a.txt"),
          ScrollbackDump(session: harness.ids[1], path: "logs/run.b.txt"),
        ])
      ])
  }

  @Test func adjustsBounds() {
    var harness = Harness()
    #expect(harness.type("\(ctrlA)b") == [.bounds(.begin)])
    #expect(
      harness.type("l\(esc)[A\(esc)[1;5B\u{08}") == [
        .bounds(.move(.right)), .bounds(.move(.up)), .bounds(.resize(.down)),
        .bounds(.resize(.left)),
      ])
    #expect(harness.type("rfp") == [.bounds(.reset), .bounds(.fillScreen), .bounds(.print)])
    #expect(harness.type("\r") == [.bounds(.accept), .retile])
    #expect(harness.state.mode == .input)
    #expect(harness.type("\(ctrlA)b\(esc)") == [.bounds(.begin), .bounds(.cancel), .retile])
  }
}
