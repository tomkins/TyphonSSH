# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

TyphonSSH (`tyssh`) is cluster SSH for macOS Terminal.app, a Swift reimagining of csshX. Requires macOS 15+ and Swift 6.4 (Swift Package Manager only, no Xcode project).

## Commands

```sh
swift build                                   # debug build
swift build -c release                        # release binary at .build/release/tyssh
swift test                                    # all tests
swift test --filter TyphonCoreTests           # one test target
swift test --filter ControllerLifecycleTests  # one suite
swift test --filter "ControllerLifecycleTests/openingHostsOpensWindowsThenTiles"  # one test
swift run tyssh --debug web1 web2             # run; --debug keeps each window's shell open after its command ends
```

Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), not XCTest. Running `tyssh` for real drives Terminal.app and needs the macOS Automation and Accessibility permissions.

## Architecture

### One binary, three process roles

`Sources/tyssh/Entry.swift` dispatches on the first argument by hand (not ArgumentParser subcommands, because the launcher's positional host arguments would swallow them):

1. **Launcher** (`tyssh <hosts>`, `Tyssh.swift` → `Launcher.swift`): loads configuration, resolves host patterns, writes a `SessionPlan` as JSON, and opens the controller window.
2. **Controller** (`tyssh _controller`, `ControllerCommand.swift` → `ControllerRuntime`): puts its tty in raw mode, listens on a Unix socket, opens one Terminal window per session, and broadcasts keystrokes.
3. **Session** (`tyssh _session <id>`, `SessionCommand.swift` → `SessionRuntime`): runs ssh on a pseudo-terminal it owns, connects to the controller's socket, sends `hello(id, tty)`, and writes the `input` bytes it receives straight into the pty. It sends `exited(code)` before quitting.

The controller finds each session's Terminal window by matching the tty from `hello` (`TerminalApp.windowID(forTTY:)`). Socket messages are `ControlMessage`s framed as a 4-byte big-endian length followed by JSON (`TyphonCore/Messaging`). `WindowCommands` in `SessionPlan.swift` builds the shell commands typed into new windows.

### Pure core, effectful shell

- **`TyphonCore`** has no I/O. `ControllerState` is a pure state machine: raw input bytes go into `handle(_:)` and come out as `[ControllerEffect]`. Modes (input, action menu, select, bounds, line editing) live in `ControllerMode`. New controller behaviour usually means a new effect case plus handling in `ControllerState`, tested by typing keys through the `Harness` in `ControllerStateTests.swift`.
- **`TyphonTerminal`** carries out effects. `ControllerRuntime` maps each `ControllerEffect` onto `TerminalApp` calls, socket writes and file writes. `TerminalApp` is a `@MainActor` protocol; `AppleTerminal` implements it with AppleScript (`AppleScriptRunner`, `TerminalScript`), and keyboard-only actions (split pane, font size) go through System Events. `ControllerRuntimeTests` substitutes a `FakeTerminal` that records calls.
- **`CTyphonSupport`** wraps the C calls Swift can't safely make (`forkpty`/`exec`, `ioctl`).

Host arguments (ranges, lists, CIDR subnets, `host+N`, cluster names, hosts files) are expanded in `TyphonCore/Hosts` (`HostListResolver`, `HostPatternExpander`). Configuration is JSON from `~/.config/tyssh/config.json` (or `$XDG_CONFIG_HOME`), then any `--config` files, then CLI overrides, merged in `ConfigurationLoader`. The README documents every configuration key and controller keybinding, so update it when either changes.

All targets enable the `ApproachableConcurrency` upcoming feature (`Package.swift`).
