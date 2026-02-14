# CobraKey

> macOS menubar utility that remaps extra mouse buttons to keyboard shortcuts

## What This Is

CobraKey sits in your menu bar and turns extra mouse button presses into keyboard shortcuts. Press a side button, get a keystroke — with any modifier combination you want. No drivers, no bloatware, no dock icon.

Built because Razer's macOS software doesn't support the Cobra mouse, but works with any mouse that has extra buttons.

## Features

| Feature | Description |
|---|---|
| Learn mode | Press a mouse button, then press a key combo — mapping done |
| Any shortcut | Map to any key with any combination of Ctrl, Option, Shift, Cmd |
| Multiple mappings | Map as many buttons as your mouse has |
| Event blocking | Optionally swallow the original mouse click so apps don't see it |
| Start at login | Launch automatically when you log in |
| Zero dependencies | Pure Swift/AppKit — no external libraries |

## Quick Start

**Requirements:** macOS 13.0 (Ventura) or later

1. Download `CobraKey.zip` from [GitHub Releases](../../releases)
2. Unzip and move `CobraKey.app` to your Applications folder
3. On first open, macOS will block the app because it's not notarized. To allow it:
   - Right-click `CobraKey.app` → **Open** → click **Open** in the dialog
   - Or run: `xattr -cr /Applications/CobraKey.app`
4. Open CobraKey — it appears in your menu bar as a mouse icon
5. Grant Accessibility permission when prompted (required to capture mouse events)
6. Click the menu bar icon → **Add Mapping...** → press a mouse button → press a keyboard shortcut

That's it. The mapping is active immediately.

## Usage

**Add a mapping:** Menu bar icon → Add Mapping... → press the mouse button → press the desired keyboard shortcut.

**Delete a mapping:** Click any existing mapping in the menu to remove it.

**Pause remapping:** Uncheck "Enabled" in the menu. Your mappings are preserved.

**Block original clicks:** Toggle "Block Original Click" to prevent the mouse button event from reaching other apps.

## Building from Source

```bash
git clone https://github.com/rolandtolnay/cobra-key.git
```

Open `CobraKey.xcodeproj` in Xcode and build (Cmd+B). The app requires Accessibility permission, so it cannot be sandboxed or distributed through the Mac App Store.

## How It Works

CobraKey uses macOS [CGEventTap](https://developer.apple.com/documentation/coregraphics/cgeventtap) to intercept mouse button events system-wide, then posts synthetic keyboard events via [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent). This requires Accessibility permission — the app will guide you through granting it on first launch.

## License

[MIT](LICENSE)
