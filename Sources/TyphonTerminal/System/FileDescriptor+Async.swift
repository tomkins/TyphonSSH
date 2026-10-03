import Dispatch
import Foundation
import System

extension FileDescriptor {
  /// Chunks of data read from the descriptor as it becomes readable, finishing
  /// at end-of-file or on error (such as `EIO` once a pty's process has exited).
  ///
  /// The descriptor is not closed when the stream ends.
  public func chunks(maximumLength: Int = 64 * 1024) -> AsyncStream<Data> {
    AsyncStream { continuation in
      let source = DispatchSource.makeReadSource(
        fileDescriptor: rawValue, queue: .global(qos: .userInteractive))
      source.setEventHandler {
        var buffer = [UInt8](repeating: 0, count: maximumLength)
        let count =
          (try? buffer.withUnsafeMutableBytes { try read(into: $0, retryOnInterrupt: true) }) ?? 0
        if count > 0 {
          continuation.yield(Data(buffer[..<count]))
        } else {
          source.cancel()
        }
      }
      source.setCancelHandler { continuation.finish() }
      continuation.onTermination = { _ in source.cancel() }
      source.resume()
    }
  }

}
