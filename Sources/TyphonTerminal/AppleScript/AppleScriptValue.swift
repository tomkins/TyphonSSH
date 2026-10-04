import CoreServices
import Foundation

/// A value returned from AppleScript, reduced to the shapes tyssh uses.
public enum AppleScriptValue: Hashable, Sendable {
  case none
  case text(String)
  case integer(Int)
  case real(Double)
  case list([AppleScriptValue])
  /// A reference to an application's object, such as `tab 1 of window id 7801`:
  /// how the object is picked out, by what, and the reference to what holds it
  /// (`.none` for the application itself).
  indirect case reference(form: ReferenceForm, key: AppleScriptValue, container: AppleScriptValue)

  public enum ReferenceForm: Hashable, Sendable {
    /// By position, as in `tab 1`.
    case index
    /// By unique ID, as in `window id 7801`.
    case id
    /// Any other way, such as by name.
    case other
  }

  init(_ descriptor: NSAppleEventDescriptor) {
    switch descriptor.descriptorType {
    case typeNull:
      self = .none
    case typeObjectSpecifier:
      let form: ReferenceForm =
        switch descriptor.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue {
        case OSType(formAbsolutePosition): .index
        case OSType(formUniqueID): .id
        default: .other
        }
      self = .reference(
        form: form,
        key: descriptor.forKeyword(AEKeyword(keyAEKeyData)).map(AppleScriptValue.init) ?? .none,
        container: descriptor.forKeyword(AEKeyword(keyAEContainer)).map(AppleScriptValue.init)
          ?? .none
      )
    case typeAEList:
      self = .list(
        (0..<descriptor.numberOfItems).map {
          AppleScriptValue(descriptor.atIndex($0 + 1)!)  // AppleScript lists are 1-based.
        })
    case typeSInt16, typeSInt32, typeSInt64, typeUInt32:
      self = .integer(Int(descriptor.int32Value))
    case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
      self = .real(descriptor.doubleValue)
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
