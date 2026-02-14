# macOS Permissions — Accessibility & Input Monitoring

## Which Permission Is Needed

**Accessibility only.** A CGEventTap that intercepts and swallows mouse events, plus CGEvent posting of synthetic keystrokes, requires Accessibility permission. Input Monitoring is NOT required for this use case.

This is confirmed by all major open-source mouse remappers: LinearMouse, Mac Mouse Fix, SensibleSideButtons, and Karabiner-Elements all use Accessibility exclusively.

## Checking Permission

```swift
import ApplicationServices

// Silent check — no system prompt
let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
)

// Check + trigger system prompt (shows the macOS permission dialog)
AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
)
```

The system prompt only shows **once per app identity**. After that, the app appears in the Accessibility list in System Settings with the toggle off. Subsequent calls with `prompt: true` do not show the dialog again.

There is also `AXIsProcessTrusted()` (no options) which does a silent check.

## What Happens Without Permission

- `CGEvent.tapCreate()` returns **nil** — does not crash or throw
- `CGEvent.post()` **silently does nothing** — no crash, no error, events simply not delivered

## Opening System Settings (macOS 13+)

```swift
let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
NSWorkspace.shared.open(url)
```

This legacy URL format works across Ventura (13), Sonoma (14), and Sequoia (15).

## Polling for Permission Changes

There is **no system notification** when permission is granted. The only way to detect a change is to poll:

```swift
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
    if AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
    ) {
        timer.invalidate()
        // Permission granted — proceed
    }
}
```

LinearMouse polls every 1 second using this approach.

After permission is granted, a CGEventTap can be created **immediately without restarting** the app.

## NSAlert for Permission Guidance

```swift
let alert = NSAlert()
alert.messageText = "Accessibility Permission Required"
alert.informativeText = """
    CobraKey needs Accessibility access to detect mouse button presses \
    and send keyboard shortcuts.

    Please enable CobraKey in:
    System Settings → Privacy & Security → Accessibility
    """
alert.alertStyle = .warning
alert.addButton(withTitle: "Open System Settings")
alert.addButton(withTitle: "Later")

let response = alert.runModal()
if response == .alertFirstButtonReturn {
    // Open settings + trigger system prompt so app appears in the list
}
```

## App Sandbox Constraint

**App Sandbox must be disabled.** Accessibility APIs (`AXIsProcessTrustedWithOptions`, `CGEvent.tapCreate`, `CGEvent.post`) do not work inside the sandbox. This means the app cannot be distributed on the Mac App Store.

## Code Signing During Development

Each new build during development may create a new code identity. macOS treats each identity as a separate app in the Accessibility list, requiring re-granting permission. This is normal during development and won't affect end users with a stable release signing identity.

## macOS Version Differences

The permission behavior is consistent across macOS 13 (Ventura), 14 (Sonoma), and 15 (Sequoia). The System Settings URL format works on all three. The main difference is cosmetic — the System Settings UI layout varies slightly between versions.

## Summary Decision Table

| API | Permission Required | Failure Mode |
|-----|-------------------|--------------|
| `CGEvent.tapCreate()` with `.defaultTap` | Accessibility | Returns nil |
| `CGEvent.post()` | Accessibility | Silently no-op |
| `AXIsProcessTrustedWithOptions()` | None | Always callable |
| `IOHIDManagerOpen()` | Input Monitoring | Returns error code |
