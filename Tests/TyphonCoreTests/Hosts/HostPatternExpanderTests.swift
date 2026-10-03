import Testing

@testable import TyphonCore

struct StubResolver: HostAddressResolver {
  var addresses: [String: String] = [:]

  func ipv4Address(of hostname: String) -> IPv4Address? {
    IPv4Address(addresses[hostname] ?? hostname)
  }
}

@Suite struct HostPatternExpanderTests {
  let expander = HostPatternExpander(
    resolver: StubResolver(addresses: ["gateway": "10.1.0.6"]), limit: 64)

  @Test(arguments: [
    ("plainhost", ["plainhost"]),
    ("web[1-3]", ["web1", "web2", "web3"]),
    ("web[01-03]", ["web01", "web02", "web03"]),
    ("web[1,3,5-6]", ["web1", "web3", "web5", "web6"]),
    ("node-[a-c].lan", ["node-a.lan", "node-b.lan", "node-c.lan"]),
    ("host-[prod,dev][a-b]", ["host-proda", "host-prodb", "host-deva", "host-devb"]),
    ("192.168.[0,2].[1-2]", ["192.168.0.1", "192.168.0.2", "192.168.2.1", "192.168.2.2"]),
    ("root@web[1-2]:2222", ["root@web1:2222", "root@web2:2222"]),
    ("db:[22,2222]", ["db:22", "db:2222"]),
    (
      "username@db[1-2]:[22,23]",
      ["username@db1:22", "username@db1:23", "username@db2:22", "username@db2:23"]
    ),
  ])
  func expands(pattern: String, expected: [String]) throws {
    #expect(try expander.expand(pattern) == expected)
  }

  @Test func expandsCIDRSubnets() throws {
    #expect(
      try expander.expand("192.168.0.0/30") == [
        "192.168.0.0", "192.168.0.1", "192.168.0.2", "192.168.0.3",
      ])
  }

  @Test func expandsDottedNetmasks() throws {
    #expect(
      try expander.expand("u@10.0.0.8/255.255.255.254:22") == ["u@10.0.0.8:22", "u@10.0.0.9:22"])
  }

  @Test func subnetStartsAtTheGivenAddress() throws {
    #expect(try expander.expand("192.168.0.14/28") == ["192.168.0.14", "192.168.0.15"])
  }

  @Test func subnetsResolveHostnames() throws {
    #expect(try expander.expand("gateway/31") == ["10.1.0.6", "10.1.0.7"])
  }

  @Test func refusesHugeExpansions() {
    #expect(throws: HostPatternError.tooManyHosts(limit: 64)) { try expander.expand("10.0.0.0/8") }
    #expect(throws: HostPatternError.tooManyHosts(limit: 64)) { try expander.expand("web[1-100]") }
  }

  @Test func reportsBadInput() {
    #expect(throws: HostPatternError.invalidNetmask("33")) { try expander.expand("10.0.0.0/33") }
    #expect(throws: HostPatternError.unresolvableHost("nowhere")) {
      try expander.expand("nowhere/24")
    }
    #expect(throws: HostPatternError.invalidRange("5-1")) { try expander.expand("web[5-1]") }
  }
}

@Suite struct RangeExpressionTests {
  @Test func alphanumericRangesUseMagicIncrement() throws {
    #expect(try RangeExpression.values(of: "x-ab") == ["x", "y", "z", "aa", "ab"])
    #expect(try RangeExpression.values(of: "a8-b1") == ["a8", "a9", "b0", "b1"])
  }

  @Test func magicIncrementCarries() {
    #expect("az".magicallyIncremented() == "ba")
    #expect("Zz".magicallyIncremented() == "AAa")
    #expect("99".magicallyIncremented() == "100")
  }

  @Test func unreachableUpperBoundIsAnError() {
    #expect(throws: HostPatternError.invalidRange("b-a")) { try RangeExpression.values(of: "b-a") }
  }
}

@Suite struct IPv4AddressTests {
  @Test func roundTrips() {
    #expect(IPv4Address("10.20.30.40")?.description == "10.20.30.40")
    #expect(IPv4Address("10.20.30.40")?.value == 0x0A14_1E28)
  }

  @Test(arguments: ["10.0.0", "10.0.0.256", "a.b.c.d", "1..2.3", ""])
  func rejectsInvalid(input: String) {
    #expect(IPv4Address(input) == nil)
  }

  @Test func systemResolverHandlesLiterals() {
    #expect(SystemHostAddressResolver().ipv4Address(of: "127.0.0.1") == IPv4Address("127.0.0.1"))
  }
}
