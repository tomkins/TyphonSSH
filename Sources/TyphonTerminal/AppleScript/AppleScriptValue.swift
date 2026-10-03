import CoreServices
import Foundation

/// A value returned from AppleScript, reduced to the shapes tyssh uses.
public enum AppleScriptValue: Hashable, Sendable {
  case none
  case text(String)
  case integer(Int)
  case real(Double)
  case boolean(Bool)
  case list([AppleScriptValue])

  init(_ descriptor: NSAppleEventDescriptor) {
    switch descriptor.descriptorType {
    case typeNull:
      self = .none
    case typeAEList:
      self = .list(
        (0..<descriptor.numberOfItems).map {
          AppleScriptValue(descriptor.atIndex($0 + 1)!)  // AppleScript lists are 1-based.
        })
    case typeSInt16, typeSInt32, typeSInt64, typeUInt32:
      self = .integer(Int(descriptor.int32Value))
    case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
      self = .real(descriptor.doubleValue)
    case typeBoolean, typeTrue, typeFalse:
      self = .boolean(descriptor.booleanValue)
    default:
      self = descriptor.stringValue.map(AppleScriptValue.text) ?? .none
    }
  }

  public var integer: Int? {
    switch self {
    case .integer(let value): value
    case .real(let value): Int(exactly: value.rounded())
    case .text(let text): Int(text)
    default: nil
    }
  }

  public var text: String? {
    if case .text(let text) = self { text } else { nil }
  }

  public var list: [AppleScriptValue]? {
    if case .list(let items) = self { items } else { nil }
  }
}
