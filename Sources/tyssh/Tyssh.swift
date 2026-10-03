import ArgumentParser
import TyphonCore

@main
struct Tyssh: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tyssh",
    abstract: "Cluster SSH for Terminal.app.",
    version: typhonVersion
  )

  func run() async throws {}
}
