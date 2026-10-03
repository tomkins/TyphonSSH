import Dispatch
import Foundation

/// Delivers a signal as an async sequence of events instead of an interrupt.
///
/// The signal's default action is disabled for as long as the stream is alive.
public func signalEvents(_ signal: Int32) -> AsyncStream<Void> {
  AsyncStream { continuation in
    let previous = Foundation.signal(signal, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signal, queue: .global())
    source.setEventHandler { continuation.yield() }
    source.setCancelHandler {
      Foundation.signal(signal, previous)
      continuation.finish()
    }
    continuation.onTermination = { _ in source.cancel() }
    source.resume()
  }
}
