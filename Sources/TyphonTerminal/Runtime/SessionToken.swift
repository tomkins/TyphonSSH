import Foundation

/// The secret a session window is started with and presents when it connects,
/// so only windows the controller opened can claim a session.
public enum SessionToken {
  /// 128 random bits as hex, from the system's cryptographic generator.
  public static func random() -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<16).map { _ in
      String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator))
    }.joined()
  }

  /// Compares tokens in time independent of where they differ.
  static func matches(_ token: String, _ expected: String) -> Bool {
    let (given, wanted) = (Array(token.utf8), Array(expected.utf8))
    guard given.count == wanted.count else { return false }
    return zip(given, wanted).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
  }
}
