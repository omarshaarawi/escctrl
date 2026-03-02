# escctrl

Remaps Caps Lock on macOS: hold it for Ctrl, tap it for Escape. Built with Tauri v2.

## How it works

Physical Caps Lock is remapped to F18 via `hidutil` at the HID driver level, so macOS never sees Caps Lock at all (no LED, no toggle). A CGEventTap intercepts the F18 events and translates them:

- **Hold** Caps Lock + press another key: that key gets Ctrl applied
- **Tap** Caps Lock (< 200ms, no other key pressed): sends Escape
- Caps Lock is fully disabled while the app is running and restored on quit

Works with built-in, USB, and Bluetooth keyboards.

## Prerequisites

- macOS 12+
- [Node.js](https://nodejs.org/) (for the Tauri CLI)
- [Rust](https://rustup.rs/)

## Setup

```bash
git clone https://github.com/omarshaarawi/escctrl.git
cd escctrl
npm install
```

## Usage

```bash
npm run dev
```

On first launch, macOS will prompt for Accessibility permission. Grant it and restart the app. Without it, the key interception does nothing.

The tray menu has:

- **Disable / Enable** — toggle the remapping on and off
- **Escape on Tap** — uncheck to use Caps Lock as Ctrl-only (no Escape on tap)
- **Launch at Login** — adds a LaunchAgent
- **Accessibility status** — opens System Settings if permission isn't granted

Settings persist across restarts in `~/Library/Application Support/com.omarshaarawi.escctrl/settings.json`.

## Building

```bash
npm run build
```

Output goes to `src-tauri/target/release/bundle/`.

## License

MIT
