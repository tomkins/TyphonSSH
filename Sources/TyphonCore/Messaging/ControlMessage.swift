import Foundation

/// Messages exchanged over the controller's Unix socket.
public enum ControlMessage: Hashable, Codable, Sendable {
  /// Sent by a session as soon as it connects.
  /// The controller finds the session's Terminal window by its `tty`.
  case hello(id: SessionID, tty: String)
  /// Sent by the controller: bytes to feed into the session as if typed.
  case input(Data)
}

/// Length-prefixed framing for `ControlMessage`s on a byte stream.
///
/// Each frame is a four-byte big-endian payload length followed by the
/// message as JSON.
public enum MessageFraming {
  public static let maximumPayloadSize = 1 << 20

  public static func encode(_ message: ControlMessage) throws -> Data {
    let payload = try JSONEncoder().encode(message)
    var frame = Data(capacity: 4 + payload.count)
    withUnsafeBytes(of: UInt32(payload.count).bigEndian) { frame.append(contentsOf: $0) }
    frame.append(payload)
    return frame
  }
}

/// Reassembles messages from bytes that may arrive split or coalesced.
public struct MessageDecoder: Sendable {
  private var buffer = Data()

  public init() {}

  public mutating func append(_ data: Data) {
    buffer.append(data)
  }

  /// Returns the next complete message, or `nil` if more bytes are needed.
  public mutating func next() throws(MessageDecodingError) -> ControlMessage? {
    guard buffer.count >= 4 else { return nil }
    let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
    guard length <= MessageFraming.maximumPayloadSize else { throw .frameTooLarge(length) }
    guard buffer.count >= 4 + length else { return nil }

    let payload = buffer.dropFirst(4).prefix(length)
    buffer = Data(buffer.dropFirst(4 + length))
    do {
      return try JSONDecoder().decode(ControlMessage.self, from: payload)
    } catch {
      throw .malformed
    }
  }

  /// Appends `data` and returns every message now complete.
  public mutating func messages(appending data: Data) throws(MessageDecodingError)
    -> [ControlMessage]
  {
    append(data)
    var messages: [ControlMessage] = []
    while let message = try next() {
      messages.append(message)
    }
    return messages
  }
}

public enum MessageDecodingError: Error, Equatable {
  case frameTooLarge(Int)
  case malformed
}
