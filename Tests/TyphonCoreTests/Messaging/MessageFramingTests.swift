import Foundation
import Testing
import TyphonCore

@Suite struct MessageFramingTests {
  let messages: [ControlMessage] = [
    .hello(id: SessionID(3), tty: "/dev/ttys004"),
    .input(Data("ls -l\r".utf8)),
    .input(Data([0x1B, 0x4F, 0x41, 0x00, 0xFF])),
    .exited(code: 255),
  ]

  @Test func roundTripsWhenDeliveredWhole() throws {
    var decoder = MessageDecoder()
    let stream = try messages.reduce(into: Data()) { $0 += try MessageFraming.encode($1) }
    #expect(try decoder.messages(appending: stream) == messages)
    #expect(try decoder.next() == nil)
  }

  @Test func roundTripsWhenDeliveredByteByByte() throws {
    var decoder = MessageDecoder()
    var received: [ControlMessage] = []
    for message in messages {
      for byte in try MessageFraming.encode(message) {
        received += try decoder.messages(appending: Data([byte]))
      }
    }
    #expect(received == messages)
  }

  @Test func rejectsOversizedFrames() {
    var decoder = MessageDecoder()
    decoder.append(Data([0x7F, 0xFF, 0xFF, 0xFF]))
    #expect(throws: MessageDecodingError.frameTooLarge(0x7FFF_FFFF)) { try decoder.next() }
  }

  @Test func rejectsGarbage() {
    var decoder = MessageDecoder()
    decoder.append(Data([0, 0, 0, 2]) + Data("{}".utf8))
    #expect(throws: MessageDecodingError.malformed) { try decoder.next() }
  }
}
