import Dispatch
import Foundation
import System
import TyphonCore

/// Listens for session connections on a Unix domain socket.
public final class MessageListener: Sendable {
  public let path: String
  private let descriptor: FileDescriptor

  /// Creates the socket at `path`, replacing any stale socket, readable only by the current user.
  public init(path: String) throws(Errno) {
    unlink(path)
    let descriptor = try makeSocket()
    let bound = try withAddress(path) { bind(descriptor.rawValue, $0, $1) }
    guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor.rawValue, 64) == 0 else {
      let error = Errno(rawValue: errno)
      try? descriptor.close()
      throw error
    }
    self.path = path
    self.descriptor = descriptor
  }

  /// Incoming connections, until the listener is closed.
  public func connections() -> AsyncStream<MessageConnection> {
    AsyncStream { continuation in
      let source = DispatchSource.makeReadSource(
        fileDescriptor: descriptor.rawValue, queue: .global())
      source.setEventHandler { [descriptor] in
        let client = accept(descriptor.rawValue, nil, nil)
        guard client >= 0 else { return }
        // The socket's directory and mode already keep other users out; check anyway.
        var user = uid_t()
        var group = gid_t()
        guard getpeereid(client, &user, &group) == 0, user == geteuid() else {
          close(client)
          return
        }
        continuation.yield(MessageConnection(descriptor: FileDescriptor(rawValue: client)))
      }
      source.setCancelHandler { continuation.finish() }
      continuation.onTermination = { _ in source.cancel() }
      source.resume()
    }
  }

  deinit {
    try? descriptor.close()
    unlink(path)
  }
}

/// A connection carrying `ControlMessage`s between the controller and a session.
public final class MessageConnection: Sendable {
  private let descriptor: FileDescriptor
  /// Writes happen off the caller's thread, so a stalled peer can't stall the controller.
  private let writes = DispatchQueue(label: "tyssh.connection.writes")

  init(descriptor: FileDescriptor) {
    self.descriptor = descriptor
    var on: Int32 = 1
    setsockopt(
      descriptor.rawValue, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
  }

  public static func connect(to path: String) throws(Errno) -> MessageConnection {
    let descriptor = try makeSocket()
    guard try withAddress(path, { Darwin.connect(descriptor.rawValue, $0, $1) }) == 0 else {
      let error = Errno(rawValue: errno)
      try? descriptor.close()
      throw error
    }
    return MessageConnection(descriptor: descriptor)
  }

  /// Queues a message for sending. Failures (such as a closed peer) are ignored;
  /// they surface as the end of `messages()`.
  public func send(_ message: ControlMessage) {
    guard let frame = try? MessageFraming.encode(message) else { return }
    send(frame: frame)
  }

  /// Queues a frame already encoded with `MessageFraming`, such as one broadcast to many sessions.
  public func send(frame: Data) {
    writes.async { [descriptor] in
      _ = try? descriptor.writeAll(frame)
    }
  }

  /// Messages from the peer, ending when it disconnects or sends something unreadable.
  public func messages() -> AsyncStream<ControlMessage> {
    let chunks = descriptor.chunks()
    return AsyncStream { continuation in
      let task = Task {
        var decoder = MessageDecoder()
        reading: for await chunk in chunks {
          do {
            for message in try decoder.messages(appending: chunk) {
              continuation.yield(message)
            }
          } catch {
            break reading
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Ends the connection once queued messages are sent; the peer sees end-of-file.
  public func close() {
    writes.async { [descriptor] in
      shutdown(descriptor.rawValue, SHUT_RDWR)
    }
  }

  deinit {
    try? descriptor.close()
  }
}

private func makeSocket() throws(Errno) -> FileDescriptor {
  let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw Errno(rawValue: errno) }
  return FileDescriptor(rawValue: descriptor)
}

/// Calls `body` with a `sockaddr_un` for `path`, returning its result.
private func withAddress<Result>(
  _ path: String,
  _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result
) throws(Errno) -> Result {
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8)
  guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
    throw Errno.fileNameTooLong
  }
  withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    buffer.copyBytes(from: bytes)
    buffer[bytes.count] = 0
  }
  let length = socklen_t(MemoryLayout<sockaddr_un>.size)
  address.sun_len = UInt8(length)

  return withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
  }
}
