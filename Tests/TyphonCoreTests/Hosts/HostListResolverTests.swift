import Testing
import TyphonCore

@Suite struct HostListResolverTests {
  let resolver = HostListResolver(
    clusters: [
      "web": ["web[1-2]", "username@web3:2222"],
      "all": ["web", "db1"],
      "loop": ["all", "loop"],
    ],
    sessionMax: 8,
    resolver: StubResolver()
  )

  @Test func expandsClustersRecursively() throws {
    let hosts = try resolver.resolve(arguments: ["all", "cache"])
    #expect(
      hosts.map(\.connectionString) == ["web1", "web2", "username@web3:2222", "db1", "cache"])
  }

  @Test func appendsHostsFileEntriesWithTheirCommands() throws {
    let entries = HostsFile.parse("web\tuptime\ndb[1-2]\n")
    let hosts = try resolver.resolve(arguments: ["cache"], hostsFileEntries: entries)
    #expect(
      hosts == [
        HostSpec(hostname: "cache"),
        HostSpec(hostname: "web1", command: "uptime"),
        HostSpec(hostname: "web2", command: "uptime"),
        HostSpec(user: "username", hostname: "web3", port: 2222, command: "uptime"),
        HostSpec(hostname: "db1"),
        HostSpec(hostname: "db2"),
      ])
  }

  @Test func detectsClusterCycles() {
    #expect(throws: HostListError.clusterCycle("loop")) {
      try resolver.resolve(arguments: ["loop"])
    }
  }

  @Test func enforcesSessionMaxAcrossArguments() {
    #expect(throws: HostListError.pattern(.tooManyHosts(limit: 8))) {
      try resolver.resolve(arguments: ["a+5", "b+4"])
    }
  }

  @Test func requiresAtLeastOneHost() {
    #expect(throws: HostListError.noHosts) { try resolver.resolve(arguments: []) }
  }

  @Test func reportsMalformedHosts() {
    #expect(throws: HostListError.host(.invalidPort("web:x"))) {
      try resolver.resolve(arguments: ["web:x"])
    }
  }
}

@Suite struct HostOrderingTests {
  let hosts = ["a1", "a2", "a3", "b1", "b2", "b3"].map { HostSpec(hostname: $0) }

  @Test func interleaves() {
    #expect(hosts.interleaved(by: 3).map(\.hostname) == ["a1", "b1", "a2", "b2", "a3", "b3"])
    #expect(hosts.interleaved(by: 4).map(\.hostname) == ["a1", "b2", "a2", "b3", "a3", "b1"])
    #expect(hosts.interleaved(by: 0) == hosts)
    #expect(hosts.interleaved(by: 10) == hosts)
  }

  @Test func sortsNaturally() {
    let unsorted = ["web10", "web2", "db1", "web1"].map { HostSpec(hostname: $0) }
    #expect(unsorted.sortedByName().map(\.hostname) == ["db1", "web1", "web2", "web10"])
  }
}

@Suite struct HostsFileTests {
  @Test func parsesEntriesAndComments() {
    let text = """
      # Production
      web[1-3]      uptime   # load
        username@db1:2222  tail -f  /var/log/syslog

      cache1
      """
    #expect(
      HostsFile.parse(text) == [
        HostsFileEntry(pattern: "web[1-3]", command: "uptime"),
        HostsFileEntry(pattern: "username@db1:2222", command: "tail -f  /var/log/syslog"),
        HostsFileEntry(pattern: "cache1"),
      ])
  }
}
