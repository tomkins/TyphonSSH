import Foundation
import Testing
import TyphonCore

@Suite struct ConfigurationLoaderTests {
  let defaultURL = URL(filePath: "/config/tyssh/config.json")
  let extraURL = URL(filePath: "/extra.json")

  func loader(_ files: [URL: String]) -> ConfigurationLoader {
    ConfigurationLoader { url in files[url].map { Data($0.utf8) } }
  }

  @Test func missingDefaultFileGivesDefaults() throws {
    let configuration = try loader([:]).load(defaultFile: defaultURL)
    #expect(configuration == Configuration())
  }

  @Test func missingExplicitFileIsAnError() {
    #expect(throws: ConfigurationError.missing("/extra.json")) {
      try loader([:]).load(defaultFile: defaultURL, additionalFiles: [extraURL])
    }
  }

  @Test func layersFilesThenOverrides() throws {
    let files = [
      defaultURL: """
      {
        "actionKey": "ctrl-b",
        "sshArguments": ["-A"],
        "tileColumns": 3,
        "colors": { "disabled": { "background": "#202020" } },
        "clusters": { "web": ["web1", "web2"], "db": ["db1"] }
      }
      """,
      extraURL: """
      { "tileColumns": 4, "screen": "1-2", "clusters": { "db": ["db2", "db3"] } }
      """,
    ]
    var overrides = Configuration.Overrides()
    overrides.login = "deploy"
    overrides.tileColumns = 5

    let configuration = try loader(files).load(
      defaultFile: defaultURL, additionalFiles: [extraURL], overrides: overrides
    )

    #expect(configuration.actionKey == ControlKey("ctrl-b"))
    #expect(configuration.sshArguments == ["-A"])
    #expect(configuration.tileColumns == 5)
    #expect(configuration.screen == .span(1, 2))
    #expect(configuration.login == "deploy")
    #expect(configuration.clusters == ["web": ["web1", "web2"], "db": ["db2", "db3"]])
    // A colour pair given in a file replaces the default pair entirely.
    #expect(configuration.colors.disabled == ColorPair(background: TerminalColor("#202020")))
    #expect(configuration.colors.controller == Configuration().colors.controller)
  }

  @Test func reportsWhereDecodingFailed() {
    let files = [defaultURL: #"{ "colors": { "selected": { "background": "blue" } } }"#]
    #expect {
      try loader(files).load(defaultFile: defaultURL)
    } throws: { error in
      guard case .invalid(let path, let reason) = error as? ConfigurationError else { return false }
      return path == defaultURL.path && reason.hasPrefix("colors.selected.background:")
    }
  }

  @Test func defaultLocationHonoursXDG() {
    #expect(
      ConfigurationLoader.defaultURL(environment: ["XDG_CONFIG_HOME": "/xdg"]).path
        == "/xdg/tyssh/config.json")
    #expect(
      ConfigurationLoader.defaultURL(environment: [:]).path.hasSuffix("/.config/tyssh/config.json"))
  }

  @Test func configurationRoundTripsThroughJSON() throws {
    var configuration = Configuration()
    configuration.screenBounds = Rect(x: 0, y: 25, width: 1440, height: 875)
    configuration.clusters = ["web": ["a", "b"]]
    let data = try JSONEncoder().encode(configuration)
    #expect(try JSONDecoder().decode(Configuration.self, from: data) == configuration)
  }
}
