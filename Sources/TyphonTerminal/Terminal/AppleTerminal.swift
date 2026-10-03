import CoreGraphics
import Foundation
import TyphonCore

/// Drives Terminal.app through AppleScript.
@MainActor
public struct AppleTerminal: TerminalApp {
  private let runner: any AppleScriptRunner
  private let waitForModifierRelease: @MainActor () -> Void

  /// - Parameters:
  ///   - waitForModifierRelease: Called before synthesising key presses, so that
  ///     keys still held from the triggering command (Ctrl, Shift) don't combine
  ///     with them.
  public init(
    runner: any AppleScriptRunner = NSAppleScriptRunner(),
    waitForModifierRelease: @escaping @MainActor () -> Void = AppleTerminal.waitForModifierRelease
  ) {
    self.runner = runner
    self.waitForModifierRelease = waitForModifierRelease
  }

  public func openWindow(running command: String) throws -> TerminalWindowID {
    // The window's ID is in the reference to the new tab, saving a search of
    // every tab for it, which grows slower with each window opened.
    guard
      case .reference(_, _, container: .reference(.id, let window, _)) = try runner.run(
        TerminalScript.openWindow(running: command)),
      let id = window.integer
    else {
      throw TerminalError.unexpectedResult("a new window")
    }
    return id
  }

  public func windowID(forTTY tty: String) throws -> TerminalWindowID? {
    try runner.run(TerminalScript.windowID(forTTY: tty)).integer
  }

  public func arrange(_ placements: [WindowPlacement]) throws {
    guard !placements.isEmpty else { return }
    try runner.run(TerminalScript.arrange(placements))
  }

  public func frame(of window: TerminalWindowID) throws -> Rect {
    let bounds = try runner.run(TerminalScript.frame(of: window)).list?.compactMap(\.integer).map(
      Double.init)
    guard let bounds, bounds.count == 4 else {
      throw TerminalError.unexpectedResult("window bounds")
    }
    return Rect(
      x: bounds[0], y: bounds[1], width: bounds[2] - bounds[0], height: bounds[3] - bounds[1])
  }

  public func setFrame(_ frame: Rect, of window: TerminalWindowID) throws {
    try runner.run(TerminalScript.setFrame(frame, of: window))
  }

  public func colors(of window: TerminalWindowID) throws -> ColorPair {
    let colors = try runner.run(TerminalScript.colors(of: window)).list?.map(
      TerminalColor.init(appleScript:))
    guard let colors, colors.count == 2 else {
      throw TerminalError.unexpectedResult("window colours")
    }
    return ColorPair(foreground: colors[0], background: colors[1])
  }

  public func setColors(_ colors: ColorPair, of window: TerminalWindowID) throws {
    guard colors.foreground != nil || colors.background != nil else { return }
    try runner.run(TerminalScript.setColors(colors, of: window))
  }

  public func setProfile(_ name: String, of window: TerminalWindowID) throws {
    try runner.run(TerminalScript.setProfile(name, of: window))
  }

  public func hide(_ windows: [TerminalWindowID]) throws {
    guard !windows.isEmpty else { return }
    try runner.run(TerminalScript.set("visible", to: false, of: windows))
  }

  public func minimize(_ windows: [TerminalWindowID]) throws {
    guard !windows.isEmpty else { return }
    try runner.run(TerminalScript.set("miniaturized", to: true, of: windows))
  }

  public func close(_ windows: [TerminalWindowID]) throws {
    guard !windows.isEmpty else { return }
    try runner.run(TerminalScript.close(windows))
  }

  public func history(of window: TerminalWindowID) throws -> String {
    guard let history = try runner.run(TerminalScript.history(of: window)).text else {
      throw TerminalError.unexpectedResult("scrollback")
    }
    return history
  }

  public func send(
    _ shortcut: TerminalShortcut, to windows: [TerminalWindowID], thenFocus focus: TerminalWindowID?
  ) throws {
    guard !windows.isEmpty else { return }
    waitForModifierRelease()
    try runner.run(TerminalScript.send(Keystroke(for: shortcut), to: windows, thenFocus: focus))
  }

  /// Polls the keyboard until no modifier keys are held, for up to two seconds.
  public static func waitForModifierRelease() {
    let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
    let deadline = Date.now.addingTimeInterval(2)
    while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty,
      Date.now < deadline
    {
      Thread.sleep(forTimeInterval: 0.02)
    }
  }
}

extension TerminalColor {
  /// Reads an AppleScript colour, a list of three 16-bit integers.
  init?(appleScript value: AppleScriptValue) {
    guard let components = value.list?.compactMap(\.integer), components.count == 3 else {
      return nil
    }
    let clamped = components.map { UInt16(clamping: $0) }
    self.init(red: clamped[0], green: clamped[1], blue: clamped[2])
  }
}
