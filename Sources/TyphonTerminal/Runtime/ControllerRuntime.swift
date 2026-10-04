import Foundation
import System
import TyphonCore

/// Runs the controller window: feeds keystrokes and session events into
/// `ControllerState`, and carries out the effects it returns.
@MainActor
public final class ControllerRuntime {
  public struct Environment {
    public var terminal: any TerminalApp
    public var screens: any ScreenProvider
    public var notifier: any Notifier
    public var output: TerminalOutput
    public var commands: WindowCommands
    public var homeDirectory: URL
    /// The controller's own tty, used to find its window.
    public var tty: String?
    /// Makes the secret each session presents when it connects.
    public var makeToken: () -> String

    public init(
      terminal: any TerminalApp,
      screens: any ScreenProvider,
      notifier: any Notifier,
      output: TerminalOutput,
      commands: WindowCommands,
      homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
      tty: String? = ttyName(.standardInput),
      makeToken: @escaping () -> String = SessionToken.random
    ) {
      self.terminal = terminal
      self.screens = screens
      self.notifier = notifier
      self.output = output
      self.commands = commands
      self.homeDirectory = homeDirectory
      self.tty = tty
      self.makeToken = makeToken
    }
  }

  public private(set) var state: ControllerState
  private let plan: SessionPlan
  private let environment: Environment
  private var configuration: Configuration { plan.configuration }
  private var terminal: any TerminalApp { environment.terminal }

  private var connections: [SessionID: MessageConnection] = [:]
  /// The token each session window was started with, until it connects.
  private var tokens: [SessionID: String] = [:]
  private var controllerWindow: TerminalWindowID?
  private var controllerColors = ColorPair()
  private var originalColors: [SessionID: ColorPair] = [:]
  /// Where sessions are tiled; changed interactively in bounds mode.
  public private(set) var tilingArea = Rect(x: 0, y: 0, width: 1024, height: 768)
  /// The configured controller height, or more if Terminal won't make the window that short.
  private var controllerHeight: Double
  private var tilingAreaBeforeEditing: Rect?

  private var shownPrompt: [String] = []
  private var shownTitle = ""
  private enum Phase { case running, quitting, finished }
  private var phase = Phase.running
  private let (stopped, stop) = AsyncStream<Void>.makeStream()

  public init(plan: SessionPlan, environment: Environment) {
    self.plan = plan
    self.environment = environment
    self.state = ControllerState(configuration: plan.configuration)
    self.controllerHeight = plan.configuration.controllerHeight
  }

  // MARK: - Running

  /// Opens the session windows and runs until the user quits or every session ends.
  public func run(listener: MessageListener) async {
    start()
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for await chunk in FileDescriptor.standardInput.chunks() {
          await self.handleInput(chunk)
        }
      }
      group.addTask {
        for await connection in listener.connections() {
          await self.accept(connection)
        }
      }
      group.addTask {
        for await _ in signalEvents(SIGWINCH) {
          await self.render(force: true)
        }
      }
      for await _ in stopped { break }
      group.cancelAll()
    }
  }

  /// Finds the controller's window, styles it, and opens a window per host.
  public func start() {
    environment.output.clearAll()
    do {
      tilingArea = try TilingArea.resolve(
        for: configuration, screens: environment.screens.visibleFrames())
    } catch {
      state.show(status: "\(error)")
    }
    setUpControllerWindow()
    perform(state.open(plan.hosts))
    render()
  }

  private func setUpControllerWindow() {
    do {
      guard let tty = environment.tty, let window = try terminal.windowID(forTTY: tty) else {
        return
      }
      controllerWindow = window
      if let profile = configuration.controllerProfile {
        try terminal.setProfile(profile, of: window)
      }
      let original = try terminal.colors(of: window)
      controllerColors = ColorPair(
        foreground: configuration.colors.controller.foreground ?? original.foreground,
        background: configuration.colors.controller.background ?? original.background
      )
      try terminal.setColors(controllerColors, of: window)
      // Settle the controller's height before the sessions open, so the
      // first tiling is the last; see `retile()`.
      try terminal.setFrame(currentLayout.controllerFrame, of: window)
      controllerHeight = max(controllerHeight, try terminal.frame(of: window).height)
    } catch {
      state.show(status: "\(error)")
    }
  }

  public func handleInput(_ bytes: Data) {
    perform(state.handle(bytes))
    render()
  }

  // MARK: - Sessions

  private func accept(_ connection: MessageConnection) {
    Task {
      var session: SessionID?
      var exitCode: Int32?
      for await message in connection.messages() {
        switch message {
        case .hello(let id, let tty, let token) where session == nil:
          guard sessionConnected(id, tty: tty, token: token, connection: connection) else {
            break
          }
          session = id
        case .exited(let code):
          exitCode = code
        default:
          break
        }
      }
      if let session {
        sessionDisconnected(session, exitCode: exitCode)
      }
    }
  }

  /// Accepts a session's connection if it presents the token its window was
  /// started with. Each token works once, so a connection can't take over a
  /// session that's already connected.
  @discardableResult
  public func sessionConnected(
    _ id: SessionID, tty: String, token: String, connection: MessageConnection
  ) -> Bool {
    guard let session = state.roster[id], phase == .running, let expected = tokens[id],
      SessionToken.matches(token, expected)
    else {
      connection.close()
      return false
    }
    tokens[id] = nil
    connections[id] = connection
    if session.windowID == nil, let window = try? terminal.windowID(forTTY: tty) {
      state.attach(windowID: window, to: id)
    }
    return true
  }

  /// Forgets a session whose connection ended.
  ///
  /// If ssh exited cleanly its window is closed too; otherwise the window is
  /// left open so any error can be read.
  public func sessionDisconnected(_ id: SessionID, exitCode: Int32? = nil) {
    connections[id] = nil
    tokens[id] = nil
    guard phase == .running else {
      if connections.isEmpty { finishQuitting() }
      return
    }
    if exitCode == 0, let window = state.roster[id]?.windowID {
      closeWhenIdle(window)
    }
    perform(state.sessionDidClose(id))
    render()
  }

  /// Closes a window once its process has had a moment to exit, so Terminal
  /// doesn't ask whether to terminate it.
  private func closeWhenIdle(_ window: TerminalWindowID) {
    Task {
      try? await Task.sleep(for: .milliseconds(300))
      try? terminal.close([window])
    }
  }

  private var sessionWindows: [TerminalWindowID] {
    state.roster.ordered.compactMap(\.windowID)
  }

  // MARK: - Effects

  private func perform(_ effects: [ControllerEffect]) {
    for effect in effects {
      do {
        try perform(effect)
      } catch {
        state.show(status: "\(error)")
        environment.output.bell()
      }
    }
  }

  private func perform(_ effect: ControllerEffect) throws {
    switch effect {
    case .send(let data, let sessions):
      let frame = try MessageFraming.encode(.input(data))
      for id in sessions {
        connections[id]?.send(frame: frame)
      }
    case .openSession(let id, let host):
      try openWindow(for: id, host: host)
    case .retile:
      try retile()
    case .zoom(let id):
      guard let window = state.roster[id]?.windowID else { return }
      let layout = currentLayout
      var placements = [WindowPlacement(window: window, frame: layout.zoomedFrame)]
      if let controllerWindow {
        placements.append(WindowPlacement(window: controllerWindow, frame: layout.controllerFrame))
      }
      try terminal.arrange(placements)
    case .setAppearances(let appearances):
      try recolor(appearances)
    case .hideSessions:
      try terminal.hide(sessionWindows)
    case .minimizeController:
      try terminal.minimize(controllerWindow.map { [$0] } ?? [])
    case .shortcut(let shortcut, let sessions, let includingController):
      var windows = sessions.compactMap { state.roster[$0]?.windowID }
      if includingController, let controllerWindow { windows.append(controllerWindow) }
      try terminal.send(shortcut, to: windows, thenFocus: controllerWindow)
    case .dumpScrollback(let dumps):
      try dumpScrollback(dumps)
    case .bounds(let command):
      try adjustBounds(command)
    case .notify(let message):
      if configuration.notifications { environment.notifier.notify(message) }
    case .bell:
      environment.output.bell()
    case .quit:
      quit()
    }
  }

  private func openWindow(for id: SessionID, host: HostSpec) throws {
    let token = environment.makeToken()
    tokens[id] = token
    let command = environment.commands.session(
      id, token: token, host: host, socketPath: plan.socketPath, configuration: configuration)
    let window: TerminalWindowID
    do {
      window = try terminal.openWindow(running: command)
    } catch {
      // Forget the session, but stay open so the error can be read.
      let effects = state.sessionDidClose(id).filter { $0 != .quit && !$0.isNotification }
      perform(effects)
      throw error
    }
    state.attach(windowID: window, to: id)
    if let profile = configuration.sessionProfile {
      try terminal.setProfile(profile, of: window)
    }
  }

  /// Recolours windows from the colours they started with, reading those the first time.
  private func recolor(_ appearances: [SessionID: SessionAppearance]) throws {
    let windows = appearances.keys.compactMap { id in state.roster[id]?.windowID.map { (id, $0) } }
    let unread = windows.filter { id, _ in originalColors[id] == nil }
    if !unread.isEmpty {
      let read = try terminal.colors(of: unread.map(\.1))
      for (id, window) in unread { originalColors[id] = read[window] }
    }
    var colors: [TerminalWindowID: ColorPair] = [:]
    for (id, window) in windows {
      guard let original = originalColors[id], let appearance = appearances[id] else { continue }
      colors[window] = appearance.colors(scheme: configuration.colors, original: original)
    }
    try terminal.setColors(colors)
  }

  private var currentLayout: GridLayout {
    GridLayout(shape: state.shape, area: tilingArea, controllerHeight: controllerHeight)
  }

  private func retile() throws {
    try arrangeAll()
    // Terminal enforces a minimum window height, growing the controller up over
    // the sessions if it's set too short. If so, lay out again around its real height.
    if let controllerWindow {
      let actualHeight = try terminal.frame(of: controllerWindow).height
      if actualHeight > controllerHeight {
        controllerHeight = actualHeight
        try arrangeAll()
      }
    }
  }

  private func arrangeAll() throws {
    let layout = currentLayout
    var placements = state.roster.ordered.enumerated().compactMap { index, session in
      session.windowID.map { WindowPlacement(window: $0, frame: layout.frame(forWindowAt: index)) }
    }
    // Last, so the controller ends up in front.
    if let controllerWindow {
      placements.append(WindowPlacement(window: controllerWindow, frame: layout.controllerFrame))
    }
    try terminal.arrange(placements)
  }

  private func dumpScrollback(_ dumps: [ScrollbackDump]) throws {
    for dump in dumps {
      guard let window = state.roster[dump.session]?.windowID else { continue }
      let url =
        dump.path.hasPrefix("/")
        ? URL(filePath: dump.path)
        : environment.homeDirectory.appending(path: dump.path)
      try writePrivately(Data(terminal.history(of: window).utf8), to: url)
    }
    if let first = dumps.first {
      state.show(
        status:
          "Saved \(dumps.count) scrollback file\(dumps.count == 1 ? "" : "s"), e.g. ~/\(first.path)"
      )
    }
  }

  /// Writes `data` readable only by the current user, as history often holds secrets.
  private func writePrivately(_ data: Data, to url: URL) throws {
    let file = try FileDescriptor.open(
      FilePath(url.path), .writeOnly, options: [.create, .truncate, .noFollow],
      permissions: .ownerReadWrite)
    try file.closeAfter {
      // An existing file keeps its mode through O_CREAT, so tighten it too.
      guard fchmod(file.rawValue, 0o600) == 0 else { throw Errno(rawValue: errno) }
      _ = try file.writeAll(data)
    }
  }

  private func adjustBounds(_ command: BoundsCommand) throws {
    guard let controllerWindow else {
      throw ControllerRuntimeError.noControllerWindow
    }
    let step = ControllerState.boundsStep
    switch command {
    case .begin:
      tilingAreaBeforeEditing = tilingArea
      try terminal.hide(sessionWindows)
      try terminal.setColors(configuration.colors.bounds, of: controllerWindow)
      try terminal.arrange([WindowPlacement(window: controllerWindow, frame: tilingArea)])
    case .move(let direction):
      let (dx, dy) = direction.offset
      try terminal.setFrame(
        terminal.frame(of: controllerWindow).offsetBy(dx: dx * step, dy: dy * step),
        of: controllerWindow)
    case .resize(let direction):
      let (dx, dy) = direction.offset
      try terminal.setFrame(
        terminal.frame(of: controllerWindow).resizedBy(dWidth: dx * step, dHeight: dy * step),
        of: controllerWindow
      )
    case .accept:
      tilingArea = try terminal.frame(of: controllerWindow)
      try terminal.setColors(controllerColors, of: controllerWindow)
    case .cancel:
      tilingArea = tilingAreaBeforeEditing ?? tilingArea
      try terminal.setColors(controllerColors, of: controllerWindow)
    case .reset:
      try terminal.setFrame(
        TilingArea.resolve(for: configuration, screens: environment.screens.visibleFrames()),
        of: controllerWindow
      )
    case .fillScreen:
      try terminal.setFrame(
        TilingArea.resolve(configuration.screen, screens: environment.screens.visibleFrames()),
        of: controllerWindow
      )
    case .print:
      let frame = try terminal.frame(of: controllerWindow)
      state.show(
        status: #"Configuration: "screenBounds": "#
          + #"{ "x": \#(Int(frame.x)), "y": \#(Int(frame.y)), "width": \#(Int(frame.width)), "height": \#(Int(frame.height)) }"#
      )
    }
  }

  // MARK: - Quitting

  /// Asks every session to end, then closes their windows.
  private func quit() {
    guard phase == .running else { return }
    phase = .quitting
    for connection in connections.values {
      connection.close()
    }
    if connections.isEmpty {
      finishQuitting()
    } else {
      // Don't wait forever on a session that won't go.
      Task {
        try? await Task.sleep(for: .seconds(2))
        finishQuitting()
      }
    }
  }

  private func finishQuitting() {
    guard phase == .quitting else { return }
    phase = .finished
    try? terminal.close(sessionWindows)
    environment.output.show(["tyssh has finished."])
    stop.yield()
    stop.finish()
  }

  // MARK: - Display

  private func render(force: Bool = false) {
    let prompt = state.prompt
    if force || prompt != shownPrompt {
      environment.output.show(prompt)
      shownPrompt = prompt
    }
    let title =
      "tyssh - " + state.roster.ordered.map(\.host.connectionString).joined(separator: ", ")
    if title != shownTitle {
      environment.output.setTitle(title)
      shownTitle = title
    }
  }
}

public enum ControllerRuntimeError: Error, CustomStringConvertible {
  case noControllerWindow

  public var description: String {
    switch self {
    case .noControllerWindow: "Couldn't find the controller's Terminal window"
    }
  }
}

extension Direction {
  /// Unit offset in top-left-origin coordinates.
  var offset: (Double, Double) {
    switch self {
    case .up: (0, -1)
    case .down: (0, 1)
    case .left: (-1, 0)
    case .right: (1, 0)
    }
  }
}

extension ControllerEffect {
  var isNotification: Bool {
    if case .notify = self { true } else { false }
  }
}
