import Testing
import TyphonCore

@Suite struct ShellWordsTests {
  @Test(arguments: [
    ("", []),
    ("-A -o  ForwardX11=no", ["-A", "-o", "ForwardX11=no"]),
    (#"-o "ProxyCommand ssh bastion" -v"#, ["-o", "ProxyCommand ssh bastion", "-v"]),
    ("'it'\\''s' x", ["it's", "x"]),
    (#"a\ b "c\"d" 'e\f'"#, ["a b", #"c"d"#, #"e\f"#]),
    ("''", [""]),
  ])
  func splits(input: String, expected: [String]) throws {
    #expect(try ShellWords.split(input) == expected)
  }

  @Test func reportsUnbalancedInput() {
    #expect(throws: ShellWordsError.unterminatedQuote) { try ShellWords.split("'abc") }
    #expect(throws: ShellWordsError.danglingEscape) { try ShellWords.split("abc\\") }
  }

  @Test func quotesOnlyWhenNeeded() {
    #expect(ShellWords.quote("web-1.example.com:22") == "web-1.example.com:22")
    #expect(ShellWords.quote("two words") == "'two words'")
    #expect(ShellWords.quote("it's") == #"'it'\''s'"#)
    #expect(ShellWords.quote("") == "''")
  }

  @Test(arguments: [["ssh", "-o", "Proxy Command", "it's", "$HOME", ""]])
  func joinRoundTripsThroughSplit(words: [String]) throws {
    #expect(try ShellWords.split(ShellWords.join(words)) == words)
  }
}
