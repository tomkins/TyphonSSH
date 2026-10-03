import Testing
import TyphonCore

@Suite struct HostSpecTests {
  @Test(arguments: [
    ("host", HostSpec(hostname: "host")),
    ("host:2222", HostSpec(hostname: "host", port: 2222)),
    ("root@host", HostSpec(user: "root", hostname: "host")),
    ("root@10.0.0.1:22", HostSpec(user: "root", hostname: "10.0.0.1", port: 22)),
  ])
  func parses(input: String, expected: HostSpec) throws {
    #expect(try HostSpec(parsing: input) == expected)
    #expect(try HostSpec(parsing: input).connectionString == input)
  }

  @Test(arguments: [
    "", "@host", "user@", "a@b@c", ":22", "-oProxyCommand=sh", "user@-oProxyCommand=sh",
    "-l@host",
  ])
  func rejectsMalformed(input: String) {
    #expect(throws: HostSpecError.malformed(input)) { try HostSpec(parsing: input) }
  }

  @Test(arguments: ["host:ssh", "host:0", "host:70000"])
  func rejectsInvalidPorts(input: String) {
    #expect(throws: HostSpecError.invalidPort(input)) { try HostSpec(parsing: input) }
  }

  @Test func sshArgumentsIncludeEverySpecifiedPart() throws {
    let spec = try HostSpec(parsing: "username@web1:2222", command: "uptime")
    #expect(
      spec.sshArguments(extraArguments: ["-A"]) == [
        "ssh", "-A", "-l", "username", "-p", "2222", "--", "web1", "uptime",
      ])
  }

  @Test func sshArgumentsFallBackToDefaults() {
    let spec = HostSpec(hostname: "web1")
    #expect(
      spec.sshArguments(ssh: "mosh", defaultUser: "deploy", defaultCommand: "top")
        == ["mosh", "-l", "deploy", "--", "web1", "top"])
    #expect(spec.sshArguments() == ["ssh", "--", "web1"])
  }

  @Test func ownUserAndCommandWinOverDefaults() {
    let spec = HostSpec(user: "username", hostname: "web1", command: "ls")
    #expect(
      spec.sshArguments(defaultUser: "deploy", defaultCommand: "top") == [
        "ssh", "-l", "username", "--", "web1", "ls",
      ])
  }
}
