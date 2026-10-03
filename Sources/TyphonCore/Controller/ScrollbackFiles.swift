/// Names the files that session scrollback is written to.
public enum ScrollbackFiles {
  public static let defaultBaseName = "Desktop/tyssh_scrollback"

  /// One path per session: `<base>.<host>.txt`, with the host reduced to
  /// filename-safe characters and suffixed `.1`, `.2`, … where hosts repeat.
  public static func paths(for sessions: [Session], baseName: String) -> [(SessionID, String)] {
    var used: Set<String> = []
    return sessions.map { session in
      let safe = String(
        session.host.connectionString.map { character in
          character.isASCII
            && (character.isLetter || character.isNumber || "-@.+()=_".contains(character))
            ? character : "_"
        })
      var name = safe
      var counter = 0
      while used.contains(name) {
        counter += 1
        name = "\(safe).\(counter)"
      }
      used.insert(name)
      return (session.id, "\(baseName).\(name).txt")
    }
  }
}
