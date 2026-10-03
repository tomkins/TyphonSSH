import Foundation
import TyphonCore

/// Runs AppleScript source. Abstracted so script generation can be tested
/// without driving real applications.
@MainActor
public protocol AppleScriptRunner {
  @discardableResult
  func run(_ source: String) throws(AppleScriptError) -> AppleScriptValue
}

/// Runs scripts in-process with `NSAppleScript`, which must be used on the main thread.
public struct NSAppleScriptRunner: AppleScriptRunner {
  public init() {}

  public func run(_ source: String) throws(AppleScriptError) -> AppleScriptValue {
    guard let script = NSAppleScript(source: source) else {
      throw AppleScriptError(number: nil, message: "Couldn't create script")
    }
    var errorInfo: NSDictionary?
    let result = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      throw AppleScriptError(
        number: errorInfo[NSAppleScript.errorNumber] as? Int,
        message: errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
      )
    }
    return AppleScriptValue(result)
  }
}

public struct AppleScriptError: Error, Equatable, CustomStringConvertible {
  public var number: Int?
  public var message: String

  public init(number: Int?, message: String) {
    self.number = number
    self.message = message
  }

  /// `errAEEventNotPermitted`: the user hasn't allowed Automation for this app.
  public var isNotPermitted: Bool { number == -1743 }

  public var description: String {
    if isNotPermitted {
      return "\(message)\nAllow Terminal to control Terminal and System Events in "
        + "System Settings › Privacy & Security › Automation."
    }
    return number.map { "\(message) (\($0))" } ?? message
  }
}

/// Helpers for writing values into AppleScript source.
enum AppleScriptLiteral {
  /// A quoted string literal.
  static func string(_ value: String) -> String {
    "\"" + value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
  }

  /// A rectangle as Terminal's `bounds`: `{left, top, right, bottom}`.
  static func bounds(_ rect: Rect) -> String {
    let values = [rect.x, rect.y, rect.maxX, rect.maxY].map { String(Int($0.rounded())) }
    return "{" + values.joined(separator: ", ") + "}"
  }
}
