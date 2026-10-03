import Foundation
import Testing
import TyphonTerminal

@Suite(.timeLimit(.minutes(1)))
struct PseudoTerminalTests {
  /// Reads output until `text` appears, or the process closes the terminal.
  func output(of terminal: PseudoTerminal, until text: String? = nil) async -> String {
    var received = ""
    for await chunk in terminal.output() {
      received += String(decoding: chunk, as: UTF8.self)
      if let text, received.contains(text) { break }
    }
    return received
  }

  @Test func feedsInputAndReadsOutput() async throws {
    let terminal = try PseudoTerminal(arguments: ["cat"])
    try terminal.send(Data("hello\r".utf8))
    // Once from the terminal's echo, once from cat.
    #expect(await output(of: terminal, until: "hello\r\nhello\r\n").hasSuffix("hello\r\nhello\r\n"))

    try terminal.send(Data([0x04]))  // Ctrl-D: end of input
    #expect(await terminal.waitForExit() == .exited(0))
  }

  @Test func reportsExitStatus() async throws {
    let terminal = try PseudoTerminal(arguments: ["/bin/sh", "-c", "exit 3"])
    #expect(await terminal.waitForExit() == .exited(3))
  }

  @Test func reportsSignals() async throws {
    let terminal = try PseudoTerminal(arguments: ["/bin/sh", "-c", "kill -TERM $$"])
    let status = await terminal.waitForExit()
    #expect(status == .signaled(SIGTERM))
    #expect(status.code == 128 + SIGTERM)
  }

  @Test func startsWithTheRequestedSizeAndResizes() async throws {
    let terminal = try PseudoTerminal(
      arguments: ["/bin/sh", "-c", "stty size; read line; stty size"],
      size: TerminalSize(rows: 40, columns: 100)
    )
    #expect(await output(of: terminal, until: "40 100\r\n").contains("40 100"))

    try terminal.resize(to: TerminalSize(rows: 50, columns: 120))
    #expect(terminal.size == TerminalSize(rows: 50, columns: 120))
    try terminal.send(Data("\r".utf8))
    #expect(await output(of: terminal).contains("50 120"))
    #expect(await terminal.waitForExit() == .exited(0))
  }

  @Test func reportsCommandsThatCannotRun() async throws {
    let terminal = try PseudoTerminal(arguments: ["tyssh-no-such-command"])
    #expect(await output(of: terminal).contains("can't run tyssh-no-such-command"))
    #expect(await terminal.waitForExit() == .exited(127))
  }
}
