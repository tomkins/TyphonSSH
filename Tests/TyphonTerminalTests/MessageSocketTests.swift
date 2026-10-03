import Foundation
import System
import Testing
import TyphonCore
import TyphonTerminal

@Suite(.timeLimit(.minutes(1)))
struct MessageSocketTests {
  @Test func exchangesMessagesUntilClosed() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "tyssh-test-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appending(path: "s.sock").path

    let listener = try MessageListener(path: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)

    let session = try MessageConnection.connect(to: path)
    session.send(.hello(id: SessionID(7), tty: "/dev/ttys009"))

    var connections = listener.connections().makeAsyncIterator()
    let controller = try #require(await connections.next())
    var fromSession = controller.messages().makeAsyncIterator()
    #expect(await fromSession.next() == .hello(id: SessionID(7), tty: "/dev/ttys009"))

    controller.send(.input(Data("uptime\r".utf8)))
    controller.close()
    var fromController: [ControlMessage] = []
    for await message in session.messages() { fromController.append(message) }
    #expect(fromController == [.input(Data("uptime\r".utf8))])
  }

  @Test func refusesOverlongPaths() {
    #expect(throws: Errno.fileNameTooLong) {
      try MessageListener(path: "/tmp/" + String(repeating: "x", count: 200))
    }
  }
}
