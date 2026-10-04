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
  /// Sessions in grid order.
  public private(set) var ordered: [Session] = []
  public var order: SessionOrder = .id {
    didSet { sort() }
  }

  public init(order: SessionOrder = .id) {
    self.order = order
  }

  public var count: Int { ordered.count }
  public var isEmpty: Bool { ordered.isEmpty }
  public var enabled: [Session] { ordered.filter(\.isEnabled) }

  public subscript(id: SessionID) -> Session? {
    get { ordered.first { $0.id == id } }
    set {
      ordered.removeAll { $0.id == id }
      if let newValue { ordered.append(newValue) }
      sort()
    }
  }

  /// Adds a session for `host` with the next unused identifier.
  public mutating func add(_ host: HostSpec) -> SessionID {
    let id = SessionID((ordered.map(\.id.rawValue).max() ?? 0) + 1)
    self[id] = Session(id: id, host: host)
    return id
  }

  @discardableResult
  public mutating func remove(_ id: SessionID) -> Session? {
    guard let index = ordered.firstIndex(where: { $0.id == id }) else { return nil }
    return ordered.remove(at: index)
  }

  public mutating func updateAll(_ update: (inout Session) -> Void) {
    for index in ordered.indices {
      update(&ordered[index])
    }
    sort()
  }

  private mutating func sort() {
    switch order {
    case .id:
      ordered.sort { $0.id < $1.id }
    case .hostname:
      ordered.sort { ($0.host.connectionString, $0.id) < ($1.host.connectionString, $1.id) }
    }
  }
}
