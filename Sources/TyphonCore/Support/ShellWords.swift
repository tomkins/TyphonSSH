/// Splitting and quoting of POSIX shell words.
public enum ShellWords {
  /// Splits a string into words the way a POSIX shell would, honouring
  /// single quotes, double quotes and backslash escapes (but not expansions).
  public static func split(_ string: String) throws(ShellWordsError) -> [String] {
    enum Quote { case single, double }

    var words: [String] = []
    var current = ""
    var inWord = false
    var quote: Quote?
    var iterator = string.makeIterator()

    while let character = iterator.next() {
      switch (quote, character) {
      case (.single, "'"), (.double, "\""):
        quote = nil
      case (.single, _):
        current.append(character)
      case (.double, "\\"):
        guard let next = iterator.next() else { throw .danglingEscape }
        if !"$`\"\\\n".contains(next) { current.append("\\") }
        current.append(next)
      case (.double, _):
        current.append(character)
      case (nil, "'"):
        quote = .single
        inWord = true
      case (nil, "\""):
        quote = .double
        inWord = true
      case (nil, "\\"):
        guard let next = iterator.next() else { throw .danglingEscape }
        current.append(next)
        inWord = true
      case (nil, let whitespace) where whitespace.isWhitespace:
        if inWord {
          words.append(current)
          current = ""
          inWord = false
        }
      case (nil, _):
        current.append(character)
        inWord = true
      }
    }
    guard quote == nil else { throw .unterminatedQuote }
    if inWord { words.append(current) }
    return words
  }

  /// Quotes a single word so a POSIX shell (or fish) reads it back verbatim.
  public static func quote(_ word: String) -> String {
    let safe =
      !word.isEmpty
      && word.allSatisfy { character in
        character.isASCII
          && (character.isLetter || character.isNumber || "@%+=:,./-_".contains(character))
      }
    if safe { return word }
    return "'" + word.replacing("'", with: #"'\''"#) + "'"
  }

  /// Joins words into a command line, quoting each as necessary.
  public static func join(_ words: [String]) -> String {
    words.map(quote).joined(separator: " ")
  }
}

public enum ShellWordsError: Error, Equatable, CustomStringConvertible {
  case unterminatedQuote
  case danglingEscape

  public var description: String {
    switch self {
    case .unterminatedQuote: "Unterminated quote in arguments"
    case .danglingEscape: "Trailing backslash in arguments"
    }
  }
}
