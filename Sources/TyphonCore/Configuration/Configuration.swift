/// Every setting that shapes a tyssh session.
///
/// Settings are layered: built-in defaults, then each configuration file in turn,
/// then command-line options. Each layer is a `Configuration.Overrides`, in which
/// an absent value leaves the previous layer's value alone.
public struct Configuration: Hashable, Codable, Sendable {
  /// The key that switches the controller from input mode to the action menu.
  public var actionKey: ControlKey = .ctrlA
  public var colors = ColorScheme()
  /// Height of the controller window, in points.
  public var controllerHeight: Double = 87
  public var screen: ScreenSelection = .main
  /// An explicit tiling area, overriding `screen`.
  public var screenBounds: Rect?
  /// Fixed number of grid columns, or `nil` to choose automatically.
  public var tileColumns: Int?
  /// Fixed number of grid rows, used only when `tileColumns` is `nil`.
  public var tileRows: Int?

  public var ssh = "ssh"
  public var sshArguments: [String] = []
  /// Command run on every host that doesn't name its own.
  public var remoteCommand: String?
  /// User for every host that doesn't name its own.
  public var login: String?

  public var sessionMax = 256
  /// Reorder hosts so every Nth host is adjacent; see `HostList.interleaved(by:)`.
  public var interleave = 0
  public var sortHosts = false

  /// Terminal.app "settings set" (profile) applied to the controller window.
  public var controllerProfile: String?
  /// Terminal.app "settings set" (profile) applied to session windows.
  public var sessionProfile: String?

  public var notifications = true
  public var clusters: [String: [String]] = [:]

  public init() {}
}

/// The colours tyssh applies to its windows.
public struct ColorScheme: Hashable, Codable, Sendable {
  public var controller = ColorPair(
    foreground: .white,
    background: TerminalColor(red: 38036, green: 0, blue: 0)
  )
  /// The window under the cursor in window-selection mode.
  public var selected = ColorPair(background: TerminalColor(red: 17990, green: 35209, blue: 53456))
  /// Windows that aren't receiving broadcast input.
  public var disabled = ColorPair(foreground: TerminalColor(red: 37779, green: 37779, blue: 37779))
  /// The controller while bounds are being adjusted.
  public var bounds = ColorPair(background: TerminalColor(red: 17990, green: 35209, blue: 53456))

  public init() {}
}

extension Configuration {
  /// One layer of settings. Every property is optional; `nil` means "inherit".
  ///
  /// This is also the on-disk format: a configuration file is a JSON object with
  /// any subset of these keys.
  public struct Overrides: Hashable, Codable, Sendable {
    public var actionKey: ControlKey?
    public var colors: ColorOverrides?
    public var controllerHeight: Double?
    public var screen: ScreenSelection?
    public var screenBounds: Rect?
    public var tileColumns: Int?
    public var tileRows: Int?
    public var ssh: String?
    public var sshArguments: [String]?
    public var remoteCommand: String?
    public var login: String?
    public var sessionMax: Int?
    public var interleave: Int?
    public var sortHosts: Bool?
    public var controllerProfile: String?
    public var sessionProfile: String?
    public var notifications: Bool?
    /// Merged with earlier layers; a cluster defined again replaces the earlier definition.
    public var clusters: [String: [String]]?

    public init() {}
  }

  /// Colour overrides. A pair that is present replaces the inherited pair as a whole,
  /// so `"disabled": {"background": "#333333"}` also removes the disabled foreground.
  public struct ColorOverrides: Hashable, Codable, Sendable {
    public var controller: ColorPair?
    public var selected: ColorPair?
    public var disabled: ColorPair?
    public var bounds: ColorPair?

    public init() {}
  }

  /// Returns this configuration with `overrides` layered on top.
  public func applying(_ overrides: Overrides) -> Configuration {
    var result = self
    func apply<Value>(_ keyPath: WritableKeyPath<Configuration, Value>, _ value: Value?) {
      if let value { result[keyPath: keyPath] = value }
    }
    func apply<Value>(_ keyPath: WritableKeyPath<Configuration, Value?>, _ value: Value?) {
      if let value { result[keyPath: keyPath] = value }
    }

    apply(\.actionKey, overrides.actionKey)
    apply(\.colors.controller, overrides.colors?.controller)
    apply(\.colors.selected, overrides.colors?.selected)
    apply(\.colors.disabled, overrides.colors?.disabled)
    apply(\.colors.bounds, overrides.colors?.bounds)
    apply(\.controllerHeight, overrides.controllerHeight)
    apply(\.screen, overrides.screen)
    apply(\.screenBounds, overrides.screenBounds)
    apply(\.tileColumns, overrides.tileColumns)
    apply(\.tileRows, overrides.tileRows)
    apply(\.ssh, overrides.ssh)
    apply(\.sshArguments, overrides.sshArguments)
    apply(\.remoteCommand, overrides.remoteCommand)
    apply(\.login, overrides.login)
    apply(\.sessionMax, overrides.sessionMax)
    apply(\.interleave, overrides.interleave)
    apply(\.sortHosts, overrides.sortHosts)
    apply(\.controllerProfile, overrides.controllerProfile)
    apply(\.sessionProfile, overrides.sessionProfile)
    apply(\.notifications, overrides.notifications)
    result.clusters.merge(overrides.clusters ?? [:]) { _, new in new }
    return result
  }
}
