# TyphonSSH

`tyssh` is cluster SSH for macOS Terminal. It opens one Terminal window per host, tiles them above a *controller* window, and anything typed in the controller goes to every enabled host.

It is a Swift reimagining of [csshX](https://github.com/brockgr/csshx).

```sh
tyssh web[1-4] username@db1:2222 cache
```

## Install

Requires macOS 15 or later. Install it with [Homebrew](https://brew.sh) from the tap in this repository:

```sh
brew tap tomkins/typhonssh https://github.com/tomkins/TyphonSSH
brew trust --formula tomkins/typhonssh/tyssh
brew install tyssh
```

`brew upgrade tyssh` picks up new releases.

Or install it by hand. Each [release](https://github.com/tomkins/TyphonSSH/releases) has a signed and notarized universal binary for Apple Silicon and Intel Macs:

```sh
curl -LO https://github.com/tomkins/TyphonSSH/releases/latest/download/tyssh-VERSION-macos-universal.tar.gz
tar -xzf tyssh-VERSION-macos-universal.tar.gz
mv tyssh /usr/local/bin/
```

To build from source instead, you need Swift 6.4:

```sh
swift build -c release
cp .build/release/tyssh /usr/local/bin/
```

The first run triggers two macOS permission prompts:

- **Automation:** Terminal must be allowed to control Terminal, and System Events for keyboard shortcuts. If you missed the prompts, enable this in *System Settings › Privacy & Security › Automation*.
- **Accessibility:** Terminal needs this for the actions that send keyboard shortcuts: split panes and font size.

macOS grants both permissions to Terminal, not to tyssh, so every program you run in Terminal gets them too. Accessibility is only needed for split panes and font size. If you don't use them, you can leave it off.

## Choosing hosts

Each argument can be a host, a host pattern, or a cluster name from your configuration.

| Argument                   | Connects to                                  |
|----------------------------|----------------------------------------------|
| `web1`, `username@web1:2222`   | One host, with optional user and port        |
| `web[1-3]`, `web[01-10]`   | A numeric range, keeping any zero padding    |
| `node-[a-c]`, `[prod,dev]` | Letter ranges and lists                      |
| `db:[22,2222]`             | Several ports on one host                    |
| `10.0.0.0/28`              | A subnet, starting at the address given      |
| `10.0.0.8/255.255.255.252` | A subnet written with a dotted netmask       |
| `production`               | Every host in the `production` cluster       |

`--hosts FILE` reads hosts from a file, or from standard input if FILE is `-`. Each line is a host, optionally followed by a command to run on it:

```
# hosts.txt
web[1-3]        tail -f /var/log/nginx/access.log
username@db1:2222   top
```

Run `tyssh --help` for all options, such as `--login`, `--columns`, `--screen 1-2`, `--ssh-args` and `--sort-hosts`.

## The controller

What you type in the controller goes to every enabled session. Press **Ctrl-A** to open the action menu, and **Esc** to close it.

| Keys           | Action |
|----------------|--------|
| `Ctrl-A`       | Send a literal Ctrl-A to the sessions |
| `c`            | Add hosts (names, patterns or clusters) |
| `r`            | Re-tile all windows (also un-hides, un-minimises and un-zooms them) |
| `g` / `G`      | Use more / fewer grid columns |
| `e`            | Select a window to enable, disable or zoom (see below) |
| `n`            | Enable every session |
| `t`            | Toggle every session between enabled and disabled |
| `Space`        | With exactly one session enabled, move input to the next one |
| `s`            | Send text: `h`ostname, `c`onnection string, window `i`d or `s`ession id |
| `o`            | Order windows by `h`ostname or `i`d |
| `b`            | Change the tiling area (see below) |
| `p` / `P`      | Split / unsplit every window's pane |
| `f` / `F`      | Smaller / bigger font everywhere |
| `d`            | Save every session's scrollback to `~/<base>.<host>.txt` |
| `h`            | Hide the sessions |
| `m` / `Ctrl-H` | Hide the sessions and minimise the controller |
| `x`            | Close everything and exit |

**Selecting windows (`e`):** move with the arrow keys or `h` `j` `k` `l`. Then press `e`nable, `d`isable or `t`oggle to change the selected window, `o` to disable all the others, or `O` to disable the others and zoom the selected one. Press `Esc` when finished.

**Tiling area (`b`):** the controller expands to cover the current tiling area. Drag and resize it with the mouse, or move it with the arrows or `h` `j` `k` `l` (hold Ctrl to resize). `Enter` accepts the new area and `Esc` cancels. `r` resets to the configured area and `f` fills the screen. `p` prints the area in a form you can paste into your configuration.

## Configuration

Settings are read from `~/.config/tyssh/config.json` (or `$XDG_CONFIG_HOME/tyssh/config.json`), then from any `--config` files, then from command-line options. Every key is optional:

```json
{
  "clusters": {
    "web": ["web[1-4]"],
    "production": ["web", "username@db1:2222"]
  },
  "login": "deploy",
  "ssh": "ssh",
  "sshArguments": ["-A", "-o", "ServerAliveInterval=30"],
  "remoteCommand": null,

  "actionKey": "ctrl-a",
  "screen": 1,
  "screenBounds": { "x": 0, "y": 25, "width": 1440, "height": 875 },
  "tileColumns": 3,
  "tileRows": null,
  "controllerHeight": 87,

  "sessionMax": 256,
  "sortHosts": false,
  "interleave": 0,
  "notifications": true,

  "controllerProfile": "Pro",
  "sessionProfile": "Quiet",

  "colors": {
    "controller": { "foreground": "#FFFFFF", "background": "{38036,0,0}" },
    "selected":   { "background": "#4689D0" },
    "disabled":   { "foreground": "#939393" },
    "bounds":     { "background": "#4689D0" }
  }
}
```

- **Colours** are written either as `#RRGGBB` or as Terminal's 16-bit `{r,g,b}`. A colour pair you set replaces the default pair entirely, so leaving a side out means that side isn't recoloured.
- **`ssh`** can name a wrapper such as `mosh`. It runs as `<ssh> <sshArguments> [-l user] [-p port] -- host [command]`, so a wrapper must accept `--` before the host. Hosts starting with `-` are rejected, so a hosts file can't slip options into ssh.
- **Profiles** are Terminal "settings sets". A session profile with a visual bell avoids a chorus of beeps.
- **`interleave`** takes every Nth host, so clusters sit side by side. For example, with `"interleave": 3`, `--columns 2` and two three-host clusters, each row shows one host from each cluster.

## How it works

```
tyssh web1 web2            launcher: resolves hosts, writes a plan, opens the controller
 └─ tyssh _controller      controller window: raw keyboard → ControllerState → effects
     ├─ tyssh _session 1   session window: ssh on its own pty
     └─ tyssh _session 2   ◀── broadcast input over a Unix socket
```

- **`TyphonCore`** holds the logic as pure Swift with no I/O: host patterns, configuration, grid layout, the wire protocol, and `ControllerState`. `ControllerState` turns keystrokes into `ControllerEffect`s.
- **`TyphonTerminal`** contains the macOS side: Terminal.app scripting behind the `TerminalApp` protocol, screens, pseudo-terminals, sockets, and the runtimes that carry out the effects.
- **`CTyphonSupport`** holds the few C calls (`forkpty`/`exec`, `ioctl`) that Swift can't safely make itself.
- **`tyssh`** is the command line.

Sessions run ssh on a pseudo-terminal they own. Broadcast keystrokes are written straight into that pseudo-terminal, which works on current macOS. csshX injected them with `TIOCSTI` instead.

### Differences from csshX

- Configuration is JSON. csshrc and `/etc/clusters` files are not read.
- Ctrl-A c accepts clusters and patterns, not only single hosts.
- Windows open with a clean screen, and windows of sessions that exit cleanly are closed. A failed session stays open so you can read the error.
- The layout makes room if Terminal won't make the controller as short as configured.
- These csshX features are gone: ping tests, Spaces support and Growl (replaced by macOS notifications). Shell completion comes from `tyssh --generate-completion-script`, and completes cluster names.

## Development

```sh
swift build
swift test
```

Use `--debug` to keep the shell open in each window after its command ends.
