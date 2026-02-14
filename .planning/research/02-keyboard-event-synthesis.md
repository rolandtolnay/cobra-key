# CGEvent — Keyboard Event Synthesis

## Virtual Key Codes

Defined in `Carbon.HIToolbox/Events.h`. Values verified against macOS SDK headers:

| Key | Constant | Hex | Decimal |
|-----|----------|-----|---------|
| O | `kVK_ANSI_O` | `0x1F` | 31 |
| E | `kVK_ANSI_E` | `0x0E` | 14 |

Virtual key codes are **layout-independent** — `0x1F` is always the physical key in the O position on a US ANSI keyboard, regardless of input method or keyboard layout. For Ctrl-modified shortcuts this is the expected behavior.

## Import Options

**Without Carbon (use raw values):**
```swift
import Cocoa  // CoreGraphics re-exported by Cocoa
let kCodeO: CGKeyCode = 0x1F
let kCodeE: CGKeyCode = 0x0E
```

**With Carbon (named constants):**
```swift
import Carbon.HIToolbox
let kCodeO = CGKeyCode(kVK_ANSI_O)  // Int32 → CGKeyCode cast needed
let kCodeE = CGKeyCode(kVK_ANSI_E)
```

`CGEvent`, `CGEventSource`, `CGEventFlags`, and `CGKeyCode` are all in CoreGraphics. No Carbon import is needed if using raw hex values.

## CGEventSource

Two relevant state IDs:

| State ID | Behavior |
|----------|----------|
| `.hidSystemState` | Events appear as if from physical hardware. Best for general keystroke injection. |
| `.combinedSessionState` | Merges hardware and software state. Session-level. |

`.hidSystemState` is recommended for synthesizing keystrokes that should be indistinguishable from real hardware input.

`CGEventSource(stateID:)` returns an optional. Passing `nil` as the source to `CGEvent(keyboardEventSource:...)` is valid — the system uses a default source.

## Creating Keyboard Events

```swift
let source = CGEventSource(stateID: .hidSystemState)

let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
```

Both return optionals — always guard/check for nil.

## Setting Modifier Flags

```swift
keyDown.flags = .maskControl        // Ctrl
keyDown.flags = [.maskControl, .maskShift]  // Ctrl+Shift (set operations)
```

**Both keyDown and keyUp events must have the same flags set.** If only keyDown has the modifier, the modifier state can get stuck in the receiving application.

## Posting Events

```swift
keyDown.post(tap: .cghidEventTap)
keyUp.post(tap: .cghidEventTap)
```

| Tap Location | Description |
|-------------|-------------|
| `.cghidEventTap` | HID level — lowest, earliest in the pipeline. Events seen by all observers. |
| `.cgSessionEventTap` | Session level — after HID processing. |
| `.cgAnnotatedSessionEventTap` | Events tagged as synthetic. |

`.cghidEventTap` paired with `.hidSystemState` source is the most reliable combination.

## Timing Between Events

- **keyDown → keyUp of the same keystroke:** No delay needed in most cases. The OS processes them in event queue order.
- **Consecutive keystrokes:** A small delay (10-50ms) may help if a target application drops rapid events, but start without delays.
- `usleep()` blocks the current thread. Use `DispatchQueue.asyncAfter` if delays are needed from the main thread.

## Permission Requirement

`CGEvent.post()` requires **Accessibility** permission. Without it, the call **silently does nothing** — no crash, no error, no exception. Events are simply not delivered.

## Complete Keystroke Example

```swift
func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { return }

    keyDown.flags = flags
    keyUp.flags = flags

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

// Ctrl+O
postKeystroke(keyCode: 0x1F, flags: .maskControl)

// Ctrl+E
postKeystroke(keyCode: 0x0E, flags: .maskControl)
```
