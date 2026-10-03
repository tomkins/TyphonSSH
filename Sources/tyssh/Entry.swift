/// Chooses between the launcher and the internal entry points used by the
/// windows it opens.
///
/// These are dispatched by hand rather than as subcommands, because the
/// launcher's positional host arguments would otherwise swallow them.
@main
enum Entry {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case ControllerCommand.configuration.commandName:
      await ControllerCommand.main(Array(arguments.dropFirst()))
    case SessionCommand.configuration.commandName:
      await SessionCommand.main(Array(arguments.dropFirst()))
    default:
      await Tyssh.main(arguments)
    }
  }
}
