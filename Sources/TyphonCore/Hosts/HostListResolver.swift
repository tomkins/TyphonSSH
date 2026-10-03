import Foundation

/// Turns command-line arguments and hosts files into the final, ordered list of hosts.
///
/// Each argument may be a cluster name (expanded recursively), a host pattern
/// (see `HostPatternExpander`), or a plain `[user@]host[:port]`.
public struct HostListResolver: Sendable {
  public var clusters: [String: [String]]
  public var expander: HostPatternExpander
  public var sessionMax: Int

  public init(
    clusters: [String: [String]] = [:],
    sessionMax: Int = 256,
    resolver: any HostAddressResolver = SystemHostAddressResolver()
  ) {
    self.clusters = clusters
    self.sessionMax = sessionMax
    self.expander = HostPatternExpander(resolver: resolver, limit: sessionMax)
  }

  public init(
    configuration: Configuration, resolver: any HostAddressResolver = SystemHostAddressResolver()
  ) {
    self.init(
      clusters: configuration.clusters, sessionMax: configuration.sessionMax, resolver: resolver)
  }

  /// Resolves arguments, then entries from hosts files, in that order.
  public func resolve(arguments: [String], hostsFileEntries: [HostsFileEntry] = [])
    throws(HostListError) -> [HostSpec]
  {
    var hosts: [HostSpec] = []
    for argument in arguments {
      try resolve(argument, command: nil, into: &hosts, visitingClusters: [])
    }
    for entry in hostsFileEntries {
      try resolve(entry.pattern, command: entry.command, into: &hosts, visitingClusters: [])
    }
    guard !hosts.isEmpty else { throw .noHosts }
    return hosts
  }

  private func resolve(
    _ argument: String,
    command: String?,
    into hosts: inout [HostSpec],
    visitingClusters: Set<String>
  ) throws(HostListError) {
    if let members = clusters[argument] {
      guard !visitingClusters.contains(argument) else { throw .clusterCycle(argument) }
      for member in members {
        try resolve(
          member, command: command, into: &hosts,
          visitingClusters: visitingClusters.union([argument]))
      }
      return
    }

    let expanded: [String]
    do {
      expanded = try expander.expand(argument)
    } catch {
      throw .pattern(error)
    }
    for name in expanded {
      guard hosts.count < sessionMax else { throw .pattern(.tooManyHosts(limit: sessionMax)) }
      do {
        hosts.append(try HostSpec(parsing: name, command: command))
      } catch {
        throw .host(error)
      }
    }
  }
}

public enum HostListError: Error, Equatable, CustomStringConvertible {
  case noHosts
  case clusterCycle(String)
  case pattern(HostPatternError)
  case host(HostSpecError)

  public var description: String {
    switch self {
    case .noHosts: "Need at least one hostname or cluster name"
    case .clusterCycle(let cluster): "Cluster [\(cluster)] includes itself"
    case .pattern(let error): error.description
    case .host(let error): error.description
    }
  }
}

extension Array where Element == HostSpec {
  /// Sorted by connection string, as `--sort-hosts` requests.
  public func sortedByName() -> [HostSpec] {
    sorted {
      $0.connectionString.localizedStandardCompare($1.connectionString) == .orderedAscending
    }
  }

  /// Takes every `stride`th host, wrapping round with an increasing offset.
  ///
  /// With two three-host clusters `a1 a2 a3 b1 b2 b3` and a stride of 3, this gives
  /// `a1 b1 a2 b2 a3 b3`, so that a two-column grid shows the clusters side by side.
  public func interleaved(by stride: Int) -> [HostSpec] {
    guard stride > 1 else { return self }
    return (0..<Swift.min(stride, count)).flatMap { offset in
      Swift.stride(from: offset, to: count, by: stride).map { self[$0] }
    }
  }
}
