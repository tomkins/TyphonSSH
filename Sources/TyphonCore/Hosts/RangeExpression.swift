/// The comma-separated list found between brackets in a host pattern,
/// such as `1-3,7` or `prod,dev` or `a-f`.
///
/// Ranges follow Perl's range semantics, which csshX users rely on:
/// numeric ranges count (keeping any zero padding, so `01-10` gives `01`…`10`),
/// and alphanumeric ranges use "magic increment" (`a-c`, `x-ab`, `a8-b1`).
enum RangeExpression {
  static func values(of expression: String) throws(HostPatternError) -> [String] {
    var values: [String] = []
    for term in expression.split(separator: ",", omittingEmptySubsequences: false) {
      values += try self.values(ofTerm: String(term))
    }
    return values
  }

  private static func values(ofTerm term: String) throws(HostPatternError) -> [String] {
    let bounds = term.split(separator: "-", omittingEmptySubsequences: false)
    guard bounds.count == 2, !bounds[0].isEmpty, !bounds[1].isEmpty else {
      guard !term.isEmpty else { throw .invalidRange(term) }
      return [term]
    }
    let lower = String(bounds[0])
    let upper = String(bounds[1])

    if let low = Int(lower), let high = Int(upper) {
      guard low <= high else { throw .invalidRange(term) }
      let width = lower.hasPrefix("0") ? lower.count : 0
      return (low...high).map { $0.padded(to: width) }
    }

    guard lower.isMagicIncrementable, upper.count >= lower.count else {
      throw .invalidRange(term)
    }
    var values = [lower]
    var current = lower
    while current != upper {
      current = current.magicallyIncremented()
      guard current.count <= upper.count else { throw .invalidRange(term) }
      values.append(current)
    }
    return values
  }
}

extension Int {
  fileprivate func padded(to width: Int) -> String {
    let digits = String(self)
    return String(repeating: "0", count: Swift.max(0, width - digits.count)) + digits
  }
}

extension String {
  /// Whether the string matches `/^[a-zA-Z]*[0-9]*$/`, the shape Perl will increment.
  var isMagicIncrementable: Bool {
    guard !isEmpty else { return false }
    let digitsStart = firstIndex(where: \.isASCIIDigit) ?? endIndex
    return self[..<digitsStart].allSatisfy(\.isASCIILetter)
      && self[digitsStart...].allSatisfy(\.isASCIIDigit)
  }

  /// Perl's string increment: `az` → `ba`, `Zz` → `AAa`, `a9` → `b0`.
  func magicallyIncremented() -> String {
    var characters = Array(self)
    for index in characters.indices.reversed() {
      switch characters[index] {
      case "z": characters[index] = "a"
      case "Z": characters[index] = "A"
      case "9": characters[index] = "0"
      case let character:
        characters[index] = Character(Unicode.Scalar(character.asciiValue! + 1))
        return String(characters)
      }
    }
    // Every position carried over, so grow on the left.
    let first: Character =
      switch characters.first {
      case "a": "a"
      case "A": "A"
      default: "1"
      }
    return String([first] + characters)
  }
}

extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
  var isASCIILetter: Bool { isASCII && isLetter }
}
