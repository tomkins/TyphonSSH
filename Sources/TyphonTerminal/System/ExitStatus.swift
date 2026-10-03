import Foundation

/// How a child process ended.
public enum ExitStatus: Hashable, Sendable {
  case exited(Int32)
  case signaled(Int32)

  /// Decodes a status from `waitpid`, standing in for the `WIFEXITED` family of macros.
  init(waitStatus status: Int32) {
    let signal = status & 0x7F
    self = signal == 0 ? .exited((status >> 8) & 0xFF) : .signaled(signal)
  }

  /// The conventional shell exit code: the status itself, or 128 + the signal number.
  public var code: Int32 {
    switch self {
    case .exited(let code): code
    case .signaled(let signal): 128 + signal
    }
  }
}

/// Waits for a child process to exit without blocking the caller's thread.
public func waitForExit(of processID: pid_t) async -> ExitStatus {
  await withCheckedContinuation { continuation in
    Thread.detachNewThread {
      var status: Int32 = 0
      while waitpid(processID, &status, 0) == -1, errno == EINTR {}
      continuation.resume(returning: ExitStatus(waitStatus: status))
    }
  }
}
