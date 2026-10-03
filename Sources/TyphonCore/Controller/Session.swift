/// One session window as the controller sees it.
public struct Session: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public var host: HostSpec
  /// Terminal's identifier for the window, once it has opened.
  public var windowID: Int?
  /// Whether broadcast input is sent to this session.
  public var isEnabled = true

  public init(id: SessionID, host: HostSpec, windowID: Int? = nil, isEnabled: Bool = true) {
    self.id = id
    self.host = host
    self.windowID = windowID
    self.isEnabled = isEnabled
  }
}

public enum SessionOrder: Hashable, Sendable {
  /// The order hosts were given in.
  case id
  case hostname
}

/// The live sessions, in display order.
public struct SessionRoster: Hashable, Sendable {
  private var sessions: [SessionID: Session] = [:]
  public var order: SessionOrder = .id

  public init(order: SessionOrder = .id) {
    self.order = order
  }

  public var count: Int { sessions.count }
  public var isEmpty: Bool { sessions.isEmpty }

  /// Sessions in grid order.
  public var ordered: [Session] {
    switch order {
    case .id:
      sessions.values.sorted { $0.id < $1.id }
    case .hostname:
      sessions.values.sorted {
        ($0.host.connectionString, $0.id) < ($1.host.connectionString, $1.id)
      }
    }
  }

  public var enabled: [Session] { ordered.filter(\.isEnabled) }

  public subscript(id: SessionID) -> Session? {
    get { sessions[id] }
    set { sessions[id] = newValue }
  }

  /// Adds a session for `host` with the next unused identifier.
  public mutating func add(_ host: HostSpec) -> SessionID {
    let id = SessionID((sessions.keys.map(\.rawValue).max() ?? 0) + 1)
    sessions[id] = Session(id: id, host: host)
    return id
  }

  @discardableResult
  public mutating func remove(_ id: SessionID) -> Session? {
    sessions.removeValue(forKey: id)
  }

  public mutating func updateAll(_ update: (inout Session) -> Void) {
    for id in sessions.keys {
      update(&sessions[id]!)
    }
  }
}
