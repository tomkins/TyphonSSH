import Foundation

/// The controller's behaviour, as a pure state machine.
///
/// Raw bytes typed into the controller go in through `handle(_:)`; what should
/// happen comes out as `ControllerEffect`s. Nothing here touches Terminal,
/// sockets or the file system, so every interaction can be tested directly.
public struct ControllerState: Sendable {
  public let configuration: Configuration
  public private(set) var roster: SessionRoster
  public private(set) var mode: ControllerMode = .input
  /// Grid columns chosen with g/G, overriding the configuration.
  public private(set) var columns: Int?
  public private(set) var zoomedSession: SessionID?
  /// A one-off message shown beneath the prompt until the next key press.
  public private(set) var status: String?

  private let hostResolver: HostListResolver

  /// How far one bounds-mode key press moves or resizes the controller, in points.
  public static let boundsStep: Double = 10

  public init(configuration: Configuration, hostResolver: HostListResolver? = nil) {
    self.configuration = configuration
    self.roster = SessionRoster(order: .id)
    self.columns = configuration.tileColumns
    self.hostResolver = hostResolver ?? HostListResolver(configuration: configuration)
  }

  // MARK: - Derived state

  public var shape: GridShape {
    GridShape(count: roster.count, columns: columns, rows: configuration.tileRows)
  }

  public var prompt: [String] {
    let lines = mode.prompt(actionKey: configuration.actionKey, canEnableNext: canEnableNext)
    return lines + (status.map { ["", $0] } ?? [])
  }

  public var appearances: [SessionID: SessionAppearance] {
    let selected = selectedSession?.id
    return Dictionary(
      uniqueKeysWithValues: roster.ordered.map { session in
        (
          session.id,
          SessionAppearance(isEnabled: session.isEnabled, isSelected: session.id == selected)
        )
      })
  }

  private var selectedSession: Session? {
    guard case .select(let index) = mode else { return nil }
    let ordered = roster.ordered
    return ordered.indices.contains(index) ? ordered[index] : nil
  }

  private var canEnableNext: Bool {
    roster.count > 1 && roster.enabled.count == 1
  }

  // MARK: - Session lifecycle

  /// Registers sessions for `hosts`, asking for their windows to be opened and then tiled.
  public mutating func open(_ hosts: [HostSpec]) -> [ControllerEffect] {
    guard !hosts.isEmpty else { return [] }
    let opened = hosts.map { host in ControllerEffect.openSession(roster.add(host), host) }
    return opened + [.retile]
  }

  /// Records the Terminal window a session is shown in.
  public mutating func attach(windowID: Int, to id: SessionID) {
    roster[id]?.windowID = windowID
  }

  /// Removes a session whose connection ended. Quits once none remain.
  public mutating func sessionDidClose(_ id: SessionID) -> [ControllerEffect] {
    guard let session = roster.remove(id) else { return [] }
    if zoomedSession == id { zoomedSession = nil }
    if case .select(let index) = mode {
      mode = .select(index: min(index, max(roster.count - 1, 0)))
    }
    if roster.isEmpty { return [.quit] }
    return [.notify("Closed \(session.host)"), .retile]
  }

  /// Shows a message beneath the prompt until the next key press.
  public mutating func show(status: String) {
    self.status = status
  }

  // MARK: - Input

  public mutating func handle(_ bytes: some Sequence<UInt8>) -> [ControllerEffect] {
    let appearancesBefore = appearances
    var effects: [ControllerEffect] = []
    var input = ArraySlice(bytes)
    status = nil

    while !input.isEmpty {
      if case .input = mode {
        forwardInput(&input, effects: &effects)
      } else if let key = KeyDecoder.next(from: &input) {
        handle(key, effects: &effects)
      }
    }

    // Recolour windows whose state changed. New windows already look right.
    let changed = appearances.filter { id, after in
      appearancesBefore[id].map { $0 != after } ?? false
    }
    if !changed.isEmpty { effects.append(.setAppearances(changed)) }
    return effects
  }

  /// In input mode, everything up to the action key is broadcast untouched.
  private mutating func forwardInput(
    _ input: inout ArraySlice<UInt8>, effects: inout [ControllerEffect]
  ) {
    let actionIndex = input.firstIndex(of: configuration.actionKey.byte)
    broadcast(Array(input[..<(actionIndex ?? input.endIndex)]), effects: &effects)
    if let actionIndex {
      input = input[(actionIndex + 1)...]
      mode = .action
    } else {
      input = []
    }
  }

  private func broadcast(_ bytes: [UInt8], effects: inout [ControllerEffect]) {
    let targets = roster.enabled.map(\.id)
    guard !bytes.isEmpty, !targets.isEmpty else { return }
    effects.append(.send(Data(KeyDecoder.applicationCursorKeys(bytes)), to: targets))
  }

  private mutating func handle(_ key: Key, effects: inout [ControllerEffect]) {
    switch mode {
    case .input: break
    case .action: handleAction(key, effects: &effects)
    case .select(let index): handleSelect(key, index: index, effects: &effects)
    case .bounds: handleBounds(key, effects: &effects)
    case .sendText: handleSendText(key, effects: &effects)
    case .sort: handleSort(key, effects: &effects)
    case .addHost(var editor):
      let outcome = editor.handle(key)
      mode = .addHost(editor)
      handleAddHost(outcome, effects: &effects)
    case .dumpScrollback(var editor):
      let outcome = editor.handle(key)
      mode = .dumpScrollback(editor)
      handleDumpScrollback(outcome, effects: &effects)
    }
  }

  // MARK: - Modes

  private mutating func handleAction(_ key: Key, effects: inout [ControllerEffect]) {
    let sessions = roster.ordered.map(\.id)
    switch key {
    case .escape:
      mode = .input
    case .control(configuration.actionKey.byte):
      broadcast([configuration.actionKey.byte], effects: &effects)
      mode = .input
    case .character("r"):
      retile(effects: &effects)
      mode = .input
    case .character("o"):
      mode = .sort
    case .character("c"):
      mode = .addHost(LineEditor())
    case .character("e"):
      unzoom(effects: &effects)
      mode = .select(index: 0)
    case .character("b"):
      effects.append(.bounds(.begin))
      mode = .bounds
    case .character("s"):
      mode = .sendText
    case .character("g"):
      columns = min(shape.columns + 1, max(roster.count, 1))
      retile(effects: &effects)
    case .character("G"):
      columns = max(shape.columns - 1, 1)
      retile(effects: &effects)
    case .character("p"):
      effects.append(.shortcut(.splitPane, sessions: sessions, includingController: false))
      retile(effects: &effects)
      mode = .input
    case .character("P"):
      effects.append(.shortcut(.closeSplitPane, sessions: sessions, includingController: false))
      retile(effects: &effects)
      mode = .input
    case .character("f"):
      effects.append(.shortcut(.smallerFont, sessions: sessions, includingController: true))
    case .character("F"):
      effects.append(.shortcut(.biggerFont, sessions: sessions, includingController: true))
    case .character("d"):
      mode = .dumpScrollback(LineEditor())
    case .character("n"):
      unzoom(effects: &effects)
      roster.updateAll { $0.isEnabled = true }
      mode = .input
    case .character("t"):
      unzoom(effects: &effects)
      roster.updateAll { $0.isEnabled.toggle() }
      mode = .input
    case .character(" "):
      enableNext(effects: &effects)
      mode = .input
    case .character("h"):
      effects.append(.hideSessions)
      mode = .input
    case .character("m"), .control(0x08):  // Ctrl-H: get everything out of the way.
      effects += [.hideSessions, .minimizeController]
      mode = .input
    case .character("x"):
      effects.append(.quit)
    default:
      effects.append(.bell)
    }
  }

  private mutating func handleSelect(_ key: Key, index: Int, effects: inout [ControllerEffect]) {
    let ordered = roster.ordered
    guard ordered.indices.contains(index) else {
      mode = .input
      return
    }
    let selected = ordered[index].id

    switch key {
    case .arrow(let direction, _):
      mode = .select(index: shape.index(movingFrom: index, direction))
    case .character(let character) where "hjkl".contains(character):
      let direction: Direction =
        switch character {
        case "h": .left
        case "j": .down
        case "k": .up
        default: .right
        }
      mode = .select(index: shape.index(movingFrom: index, direction))
    case .escape, .enter:
      mode = .input
    case .character("e"):
      roster[selected]?.isEnabled = true
    case .character("d"):
      roster[selected]?.isEnabled = false
    case .character("t"):
      roster[selected]?.isEnabled.toggle()
    case .character("o"):
      enableOnly(selected)
      effects.append(.notify("Enabled only \(ordered[index].host)"))
      mode = .input
    case .character("O"):
      enableOnly(selected)
      zoomedSession = selected
      effects += [.zoom(selected), .notify("Zoomed \(ordered[index].host)")]
      mode = .input
    default:
      effects.append(.bell)
    }
  }

  private mutating func handleBounds(_ key: Key, effects: inout [ControllerEffect]) {
    let command: BoundsCommand
    switch key {
    case .arrow(let direction, modified: true): command = .resize(direction)
    case .arrow(let direction, modified: false): command = .move(direction)
    case .control(0x08): command = .resize(.left)  // Ctrl-H
    case .control(0x0A): command = .resize(.down)  // Ctrl-J
    case .control(0x0B): command = .resize(.up)  // Ctrl-K
    case .control(0x0C): command = .resize(.right)  // Ctrl-L
    case .character("h"): command = .move(.left)
    case .character("j"): command = .move(.down)
    case .character("k"): command = .move(.up)
    case .character("l"): command = .move(.right)
    case .character("r"): command = .reset
    case .character("f"): command = .fillScreen
    case .character("p"): command = .print
    case .enter: command = .accept
    case .escape: command = .cancel
    default:
      effects.append(.bell)
      return
    }

    effects.append(.bounds(command))
    if command == .accept || command == .cancel {
      retile(effects: &effects)
      mode = .input
    }
  }

  private mutating func handleSendText(_ key: Key, effects: inout [ControllerEffect]) {
    let text: (Session) -> String?
    switch key {
    case .character("h"): text = { $0.host.hostname }
    case .character("c"): text = { $0.host.connectionString }
    case .character("i"): text = { $0.windowID.map(String.init) }
    case .character("s"): text = { $0.id.description }
    case .escape:
      mode = .input
      return
    default:
      effects.append(.bell)
      return
    }
    for session in roster.enabled {
      if let string = text(session) {
        effects.append(.send(Data(string.utf8), to: [session.id]))
      }
    }
    mode = .input
  }

  private mutating func handleSort(_ key: Key, effects: inout [ControllerEffect]) {
    switch key {
    case .character("h"):
      roster.order = .hostname
      retile(effects: &effects)
      mode = .input
    case .character("i"):
      roster.order = .id
      retile(effects: &effects)
      mode = .input
    case .escape:
      mode = .input
    default:
      effects.append(.bell)
    }
  }

  private mutating func handleAddHost(
    _ outcome: LineEditor.Outcome, effects: inout [ControllerEffect]
  ) {
    switch outcome {
    case .editing:
      return
    case .cancelled, .submitted(""):
      mode = .input
    case .submitted(let text):
      mode = .input
      do {
        let arguments = try ShellWords.split(text)
        let hosts = try hostResolver.resolve(arguments: arguments)
        guard roster.count + hosts.count <= configuration.sessionMax else {
          throw HostListError.pattern(.tooManyHosts(limit: configuration.sessionMax))
        }
        effects += open(hosts)
      } catch {
        status = "\(error)"
        effects.append(.bell)
      }
    }
  }

  private mutating func handleDumpScrollback(
    _ outcome: LineEditor.Outcome, effects: inout [ControllerEffect]
  ) {
    switch outcome {
    case .editing:
      return
    case .cancelled:
      mode = .input
    case .submitted(let text):
      let baseName = text.isEmpty ? ScrollbackFiles.defaultBaseName : text
      let dumps = ScrollbackFiles.paths(for: roster.ordered, baseName: baseName)
        .map { ScrollbackDump(session: $0, path: $1) }
      effects.append(.dumpScrollback(dumps))
      mode = .input
    }
  }

  // MARK: - Helpers

  private mutating func retile(effects: inout [ControllerEffect]) {
    zoomedSession = nil
    effects.append(.retile)
  }

  private mutating func unzoom(effects: inout [ControllerEffect]) {
    if zoomedSession != nil {
      retile(effects: &effects)
    }
  }

  private mutating func enableOnly(_ id: SessionID) {
    roster.updateAll { $0.isEnabled = $0.id == id }
  }

  /// When exactly one session is enabled, moves input on to the next one.
  private mutating func enableNext(effects: inout [ControllerEffect]) {
    guard canEnableNext else {
      effects.append(.bell)
      return
    }
    let ordered = roster.ordered
    let current = ordered.firstIndex(where: \.isEnabled)!
    let next = ordered[(current + 1) % ordered.count]
    enableOnly(next.id)
    effects.append(.notify("Enabled next \(next.host)"))
    if zoomedSession == ordered[current].id {
      zoomedSession = next.id
      effects += [.retile, .zoom(next.id)]
    }
  }
}
