# escctrl

Remaps Caps Lock on macOS: **hold** it for Ctrl, **tap** it for Escape. A tiny headless
background agent, controlled from the command line. No menu bar icon, no Dock icon, no window.

## How it works

Physical Caps Lock is remapped to F18 via `hidutil` at the HID driver level, so macOS never sees
Caps Lock at all (no LED, no toggle). A `CGEventTap` intercepts the F18 events and translates them:

- **Hold** Caps Lock + press another key → that key gets Ctrl applied
- **Tap** Caps Lock (< 200ms, nothing else pressed) → sends Escape
- Caps Lock is fully disabled while the agent runs and restored on quit

Works with built-in, USB, and Bluetooth keyboards.

The agent is a single Swift binary that plays two roles depending on how it's invoked: with no
arguments (how `launchd` starts it) it runs as the daemon; with a subcommand it's a CLI client
that talks to the running daemon over a Unix socket.

## Requirements

- macOS 13+
- [Swift / Xcode](https://developer.apple.com/xcode/) toolchain (to build)
- [`just`](https://github.com/casey/just) (optional, for the task shortcuts)

## Install

```bash
git clone https://github.com/omarshaarawi/escctrl.git
cd escctrl
just install        # builds, signs (ad-hoc), copies to /Applications, symlinks the `escctrl` CLI
open -a escctrl     # first launch: grant Accessibility when prompted, then it just runs
escctrl login on    # optional: launch at login
```

`just install` symlinks the CLI into `/usr/local/bin`. If that isn't writable, prefix with `sudo`
or edit `cli_dir` in the `justfile`.

> Ad-hoc signing means macOS treats each rebuild as a new app, so you'll have to re-grant
> Accessibility after rebuilding. A real Developer ID signature (used by the release builds)
> keeps the grant stable.

## Usage

The agent has no UI. Everything is the CLI:

```
escctrl status         show current state
escctrl on | off       enable / disable remapping
escctrl escape on|off   Escape-on-tap (off = Ctrl-only)
escctrl login on|off    launch at login
escctrl update         check for updates now
escctrl quit           stop the agent
```

```console
$ escctrl status
escctrl v1.1.0
  remapping:        enabled
  escape-on-tap:    on
  launch-at-login:  on
  accessibility:    granted
```

Settings persist in `UserDefaults` (under `com.omarshaarawi.escctrl`). Diagnostics go to the
unified log (`log stream --predicate 'subsystem == "com.omarshaarawi.escctrl"'`) and to
`~/Library/Logs/escctrl.log`.

## Development

```bash
just build          # debug build
just run            # run the agent in the foreground
just bundle         # assemble dist/escctrl.app (ad-hoc signed, host arch)
just bundle-universal
just format
just clean
```

The whole thing is ~600 lines of Swift under `Sources/escctrl/`. The interesting part is
`KeyboardEngine.swift` (the event tap) and `CapsLockTracker.swift` (the tap-vs-hold timing).

## Releasing

Tagging `vX.Y.Z` triggers `.github/workflows/release.yml`, which builds a universal binary
(ad-hoc signed), packages it, signs the archive for Sparkle, generates `appcast.xml`, and
attaches both to a draft GitHub release.

Builds are **ad-hoc signed** (no Apple Developer ID). The first manual install therefore hits
Gatekeeper once (right-click the app → **Open**); after that, updates Sparkle installs in place
launch normally, because Sparkle gates updates on the EdDSA signature rather than code signing.

The only repository secret it needs is `SPARKLE_PRIVATE_KEY`. The public EdDSA key is already set
in `Resources/Info.plist` → `SUPublicEDKey`; its private half lives in the login Keychain of the
machine that ran `generate_keys`. Export it for CI with `generate_keys -x sparkle_private_key` and
store the file's contents as `SPARKLE_PRIVATE_KEY`. (Generating a *new* key pair would orphan
already-installed copies, so reuse this one.)

## Updates

The agent checks the appcast daily and installs updates in the background (Sparkle). The feed is
the `appcast.xml` attached to the latest GitHub release. `escctrl update` forces a check.

## License

MIT
