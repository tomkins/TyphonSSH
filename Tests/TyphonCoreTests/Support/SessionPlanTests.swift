import Foundation
import Testing
import TyphonCore

@Suite struct SessionPlanTests {
  @Test func roundTripsThroughJSON() throws {
    var configuration = Configuration()
    configuration.login = "deploy"
    let plan = SessionPlan(
      configuration: configuration,
      hosts: [HostSpec(user: "username", hostname: "web1", port: 2222, command: "uptime")],
      socketPath: "/tmp/tyssh/control.sock",
      debug: true
    )
    #expect(try SessionPlan.decode(from: plan.encoded()) == plan)
  }
}

@Suite struct WindowCommandsTests {
  let commands = WindowCommands(executable: "/opt/tyssh dir/tyssh")

  @Test func controllerCommandExecsTheController() {
    #expect(
      commands.controller(planPath: "/tmp/x/plan.json")
        == " exec '/opt/tyssh dir/tyssh' _controller --plan /tmp/x/plan.json")
  }

  @Test func sessionCommandCarriesTheSSHInvocation() {
    var configuration = Configuration()
    configuration.ssh = "/usr/bin/ssh"
    configuration.sshArguments = ["-o", "ServerAliveInterval 30"]
    configuration.login = "deploy"
    configuration.remoteCommand = "tail -f /var/log/system.log"

    let command = commands.session(
      SessionID(3), token: "c0ffee", host: HostSpec(hostname: "web1", port: 2222),
      socketPath: "/tmp/s.sock",
      configuration: configuration
    )
    #expect(
      command
        == " exec '/opt/tyssh dir/tyssh' _session --socket /tmp/s.sock --id 3 --token c0ffee --title web1:2222 -- "
        + "/usr/bin/ssh -o 'ServerAliveInterval 30' -l deploy -p 2222 -- web1 'tail -f /var/log/system.log'"
    )
  }

  @Test func debugModeKeepsTheShell() {
    let debug = WindowCommands(executable: "/bin/tyssh", debug: true)
    #expect(debug.controller(planPath: "/p") == " /bin/tyssh _controller --plan /p")
  }
}
