/// Expands host patterns into the individual hosts they describe.
///
/// Supported forms, which may be combined:
///
/// | Pattern                      | Expands to                                  |
/// |------------------------------|---------------------------------------------|
/// | `web[1-3]`                   | `web1`, `web2`, `web3`                      |
/// | `host-[prod,dev][a-b]`       | `host-proda`, `host-prodb`, `host-deva`, …  |
/// | `db:[22,2222]`               | `db:22`, `db:2222`                          |
/// | `192.168.0.0/30`             | `192.168.0.0` … `192.168.0.3`               |
/// | `10.0.0.8/255.255.255.252`   | `10.0.0.8` … `10.0.0.11`                    |
/// | `localhost+3`                | `localhost` three times                     |
///
/// As in csshX, a subnet starts at the given address rather than the network
/// address, so `192.168.0.14/28` yields only `.14` and `.15`.
public struct HostPatternExpander: Sendable {
  public var resolver: any HostAddressResolver
  /// The most hosts a single pattern may expand to, guarding against e.g. `10.0.0.0/8`.
  public var limit: Int

  public init(resolver: any HostAddressResolver = SystemHostAddressResolver(), limit: Int = 256) {
    self.resolver = resolver
    self.limit = limit
  }

  /// Fully expands `pattern`. A plain hostname expands to itself.
  public func expand(_ pattern: String) throws(HostPatternError) -> [String] {
    var results: [String] = []
    try expand(pattern, into: &results)
    return results
  }

  private func expand(_ pattern: String, into results: inout [String]) throws(HostPatternError) {
    if let (base, count) = repetition(in: pattern) {
      let expanded = try expand(base)
      for _ in 0..<count {
        try append(expanded, to: &results)
      }
      return
    }

    guard let (user, host, port) = HostSpec.split(pattern) else {
      // Not something we can decompose; leave validation to `HostSpec`.
      return try append([pattern], to: &results)
    }
    let userPrefix = user.map { "\($0)@" } ?? ""
    let portSuffix = port.map { ":\($0)" } ?? ""

    // Hosts expand before ports, so the host varies slowest: db1:22, db1:23, db2:22, …
    if let slash = host.firstIndex(of: "/") {
      let addresses = try subnet(
        host: String(host[..<slash]),
        mask: String(host[host.index(after: slash)...])
      )
      for address in addresses {
        try expand("\(userPrefix)\(address)\(portSuffix)", into: &results)
      }
    } else if let open = host.firstIndex(of: "["),
      let close = host[open...].firstIndex(of: "]")
    {
      let prefix = host[..<open]
      let suffix = host[host.index(after: close)...]
      let expression = String(host[host.index(after: open)..<close])
      for value in try RangeExpression.values(of: expression) {
        try expand("\(userPrefix)\(prefix)\(value)\(suffix)\(portSuffix)", into: &results)
      }
    } else if let port, let ports = bracketed(port) {
      for value in try RangeExpression.values(of: ports) {
        try expand("\(userPrefix)\(host):\(value)", into: &results)
      }
    } else {
      try append([pattern], to: &results)
    }
  }

  private func append(_ hosts: [String], to results: inout [String]) throws(HostPatternError) {
    guard results.count + hosts.count <= limit else { throw .tooManyHosts(limit: limit) }
    results += hosts
  }

  /// Matches `base+N`.
  private func repetition(in pattern: String) -> (String, Int)? {
    guard let plus = pattern.lastIndex(of: "+") else { return nil }
    let base = String(pattern[..<plus])
    guard !base.isEmpty, let count = Int(pattern[pattern.index(after: plus)...]), count > 0 else {
      return nil
    }
    return (base, count)
  }

  private func bracketed(_ text: String) -> String? {
    guard text.count > 2, text.first == "[", text.last == "]" else { return nil }
    return String(text.dropFirst().dropLast())
  }

  private func subnet(host: String, mask: String) throws(HostPatternError) -> [IPv4Address] {
    guard let start = resolver.ipv4Address(of: host) else {
      throw .unresolvableHost(host)
    }

    let maskValue: UInt32
    if let prefixLength = Int(mask), (0...32).contains(prefixLength) {
      maskValue = prefixLength == 0 ? 0 : UInt32.max << (32 - prefixLength)
    } else if let dotted = IPv4Address(mask) {
      maskValue = dotted.value
    } else {
      throw .invalidNetmask(mask)
    }

    let end = start.value | ~maskValue
    let count = UInt64(end - start.value) + 1
    guard count <= UInt64(limit) else { throw .tooManyHosts(limit: limit) }
    return (start.value...end).map(IPv4Address.init)
  }
}

public enum HostPatternError: Error, Equatable, CustomStringConvertible {
  case invalidRange(String)
  case invalidNetmask(String)
  case unresolvableHost(String)
  case tooManyHosts(limit: Int)

  public var description: String {
    switch self {
    case .invalidRange(let range): "Invalid range [\(range)]"
    case .invalidNetmask(let mask): "Invalid netmask [\(mask)]"
    case .unresolvableHost(let host): "Can't resolve host [\(host)] for subnet"
    case .tooManyHosts(let limit):
      "Too many hosts (limit \(limit)); use --session-max if you need more"
    }
  }
}
