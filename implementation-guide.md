# CobraKey Implementation Guide

> Companion document to `brief.md`. Contains all technical research, verified code snippets, and implementation details needed to build the app end-to-end.

---

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [App Architecture & File Structure](#2-app-architecture--file-structure)
3. [Entry Point & App Lifecycle](#3-entry-point--app-lifecycle)
4. [Menubar UI (NSStatusItem)](#4-menubar-ui-nsstatusitem)
5. [Settings / UserDefaults Data Model](#5-settings--userdefaults-data-model)
6. [Permissions Handling](#6-permissions-handling)
7. [Event Tap — Mouse Button Capture](#7-event-tap--mouse-button-capture)
8. [Keyboard Event Synthesis](#8-keyboard-event-synthesis)
9. [Learn Mode](#9-learn-mode)
10. [Start at Login (Nice-to-Have)](#10-start-at-login-nice-to-have)
11. [IOHIDManager Fallback (Only If Needed)](#11-iohidmanager-fallback-only-if-needed)
12. [Known Gotchas & Edge Cases](#12-known-gotchas--edge-cases)

---

## 1. Project Setup

### Xcode Configuration

- **Template:** macOS > App (AppKit, Swift)
- **Deployment Target:** macOS 13.0 (Ventura)
- **Signing:** Sign locally (Development). App Sandbox **must be disabled** — Accessibility APIs do not work in sandbox
- **Cannot distribute on Mac App Store** (no sandbox = no App Store)

### Info.plist

Add this key to hide the Dock icon:

```xml
<key>LSUIElement</key>
<true/>
```

In Xcode GUI: select target → Info tab → add `Application is agent (UIElement)` = `YES`.

### No XIB/Storyboard Needed

Delete `MainMenu.xib` if Xcode generates one. Everything is built programmatically. Remove the `NSMainNibFile` / `NSMainStoryboardFile` key from Info.plist if present.

### No Third-Party Dependencies

All APIs used are from system frameworks: `Cocoa`, `CoreGraphics`, `ApplicationServices`, `Carbon.HIToolbox` (constants only), `ServiceManagement`.

---

## 2. App Architecture & File Structure

```
CobraKey/
  CobraKey/
    AppDelegate.swift          — @main entry, NSStatusItem, NSMenu, lifecycle
    EventTapManager.swift      — CGEventTap creation, mouse event capture, swallowing
    KeySynthesizer.swift       — CGEvent keyboard posting (Ctrl+O, Ctrl+E)
    PermissionManager.swift    — AXIsProcessTrustedWithOptions, permission flow
    Settings.swift             — UserDefaults wrapper (enum with static properties)
    Info.plist                 — LSUIElement = YES
    Assets.xcassets/           — (optional) custom menubar icon
    CobraKey.entitlements      — (default, no special entitlements needed)
  CobraKey.xcodeproj
```

### Responsibility Summary

| File | Responsibility |
|------|---------------|
| `AppDelegate` | Creates status item & menu. Wires everything together. Owns EventTapManager and coordinates learn mode. |
| `EventTapManager` | Creates/destroys the CGEventTap. Calls back to AppDelegate with button events. Handles tap timeout re-enable. |
| `KeySynthesizer` | Single static function to post a keystroke with modifier flags. |
| `PermissionManager` | Checks accessibility permission, shows guidance alert, opens System Settings, polls for permission changes. |
| `Settings` | Thin wrapper over UserDefaults with typed static properties. |

---

## 3. Entry Point & App Lifecycle

Use the `@main` attribute directly on `AppDelegate` — no separate `App.swift` or `main.swift` needed:

```swift
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var eventTapManager: EventTapManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        setupStatusItem()
        buildMenu()
        checkPermissionsAndStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running with no windows
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
```

---

## 4. Menubar UI (NSStatusItem)

### Status Item Creation

```swift
private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
        // SF Symbol options: "keyboard", "cursorarrow.click", "command"
        button.image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "CobraKey"
        )
    }
}
```

### Menu Construction

Per the brief, the menu has: Enabled toggle, separator, Learn A, Learn B, separator, Quit.

```swift
private var enabledItem: NSMenuItem!
private var learnAItem: NSMenuItem!
private var learnBItem: NSMenuItem!

private func buildMenu() {
    let menu = NSMenu()

    // 1. Enabled checkbox
    enabledItem = NSMenuItem(
        title: "Enabled",
        action: #selector(toggleEnabled(_:)),
        keyEquivalent: ""
    )
    enabledItem.target = self
    enabledItem.state = Settings.isEnabled ? .on : .off
    menu.addItem(enabledItem)

    // 2. Separator
    menu.addItem(.separator())

    // 3. Learn Button A
    learnAItem = NSMenuItem(
        title: learnTitle(for: .a),
        action: #selector(learnButtonA(_:)),
        keyEquivalent: ""
    )
    learnAItem.target = self
    menu.addItem(learnAItem)

    // 4. Learn Button B
    learnBItem = NSMenuItem(
        title: learnTitle(for: .b),
        action: #selector(learnButtonB(_:)),
        keyEquivalent: ""
    )
    learnBItem.target = self
    menu.addItem(learnBItem)

    // 5. Separator
    menu.addItem(.separator())

    // 6. Quit
    let quitItem = NSMenuItem(
        title: "Quit CobraKey",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    statusItem.menu = menu
}
```

### Dynamic Menu Item Updates

Hold references to menu items and mutate `.title` and `.state` directly:

```swift
// When entering learn mode:
learnAItem.title = "Press the mouse button now..."

// After learning:
learnAItem.title = "Learn Button A (current: 3)"

// Toggle checkbox:
enabledItem.state = Settings.isEnabled ? .on : .off
```

**Tip:** Implement `NSMenuDelegate.menuWillOpen(_:)` to refresh all menu item states right before the menu appears:

```swift
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        enabledItem.state = Settings.isEnabled ? .on : .off
        learnAItem.title = learnTitle(for: .a)
        learnBItem.title = learnTitle(for: .b)
    }
}

// Don't forget: menu.delegate = self
```

### Helper for Learn Titles

```swift
enum MappedButton { case a, b }

private func learnTitle(for button: MappedButton) -> String {
    let label = button == .a ? "A" : "B"
    let shortcut = button == .a ? "Ctrl+O" : "Ctrl+E"
    switch button {
    case .a:
        if let num = Settings.buttonA {
            return "Learn Button A (button \(num) → \(shortcut))"
        }
        return "Learn Button A..."
    case .b:
        if let num = Settings.buttonB {
            return "Learn Button B (button \(num) → \(shortcut))"
        }
        return "Learn Button B..."
    }
}
```

### Icon Notes

- SF Symbols adapt to light/dark mode automatically
- For a custom image: use 16x16pt PNG, set `image.isTemplate = true`
- Good symbol candidates: `keyboard`, `cursorarrow.click`, `command`, `bolt`

---

## 5. Settings / UserDefaults Data Model

```swift
import Foundation

enum Settings {
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let buttonA = "buttonA"
        static let buttonB = "buttonB"
        static let swallowEvents = "swallowEvents"
        static let hasShownPermissionHelp = "hasShownPermissionHelp"
    }

    /// Call once in applicationDidFinishLaunching
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.isEnabled: true,
            Keys.swallowEvents: true,
            Keys.hasShownPermissionHelp: false
        ])
        // buttonA and buttonB intentionally omitted — nil is the default
    }

    // MARK: - Bool properties

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isEnabled) }
    }

    static var swallowEvents: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.swallowEvents) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.swallowEvents) }
    }

    static var hasShownPermissionHelp: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasShownPermissionHelp) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasShownPermissionHelp) }
    }

    // MARK: - Optional Int properties

    static var buttonA: Int? {
        get {
            guard UserDefaults.standard.object(forKey: Keys.buttonA) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: Keys.buttonA)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Keys.buttonA)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.buttonA)
            }
        }
    }

    static var buttonB: Int? {
        get {
            guard UserDefaults.standard.object(forKey: Keys.buttonB) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: Keys.buttonB)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Keys.buttonB)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.buttonB)
            }
        }
    }
}
```

### Key Detail: Optional Int in UserDefaults

`UserDefaults.integer(forKey:)` returns `0` when the key is absent — it cannot distinguish "not set" from "set to 0". Always check `object(forKey:) != nil` first. Use `removeObject(forKey:)` to clear back to nil.

---

## 6. Permissions Handling

### Which Permission Is Needed

**Accessibility only.** A CGEventTap that intercepts and swallows mouse events needs Accessibility permission. Input Monitoring is NOT required. This is confirmed by all major open-source mouse remappers (LinearMouse, Mac Mouse Fix, SensibleSideButtons, Karabiner-Elements).

### Checking Permission

```swift
import ApplicationServices

/// Check without prompting
func isAccessibilityGranted() -> Bool {
    return AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
    )
}

/// Check and trigger system prompt (shows once per app identity)
func promptAccessibility() {
    AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    )
}
```

### What Happens Without Permission

`CGEvent.tapCreate()` **returns nil** — it does not crash or throw. Always check for nil return.

### Opening System Settings (macOS 13+)

```swift
let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
NSWorkspace.shared.open(url)
```

This legacy URL scheme works on Ventura, Sonoma, and Sequoia.

### Polling for Permission Changes

There is **no system notification** when permission changes. You must poll:

```swift
private var permissionTimer: Timer?

func startPollingForPermission() {
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        if self?.isAccessibilityGranted() == true {
            self?.permissionTimer?.invalidate()
            self?.permissionTimer = nil
            self?.onPermissionGranted()
        }
    }
}
```

After permission is granted, the CGEventTap can be created **immediately without restarting** the app.

### Best Practice Permission Flow

```
App Launch
  └─ Check AXIsProcessTrustedWithOptions (prompt: false)
       ├─ Granted → Create event tap, start normally
       └─ Not granted
            ├─ hasShownPermissionHelp == false?
            │    └─ Show NSAlert explaining why permission is needed
            │       └─ "Open System Settings" button
            │            ├─ Open Accessibility pane via URL
            │            ├─ Call promptAccessibility() to ensure app appears in list
            │            └─ Set hasShownPermissionHelp = true
            └─ Start polling every 1 second
                 └─ When granted → Create event tap, start normally
```

### NSAlert for Permission Guidance

```swift
func showPermissionAlert() {
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        promptAccessibility()  // Ensure app appears in the list
    }

    Settings.hasShownPermissionHelp = true
}
```

### Development Note: Code Signing

During development, each new build may be treated as a new app identity by macOS. You may need to re-grant Accessibility permission after rebuilding. This is normal and won't affect end users with a properly signed release build.

---

## 7. Event Tap — Mouse Button Capture

### Mouse Button Numbering on macOS

| Button | Number | CGEvent Type |
|--------|--------|-------------|
| Left click | 0 | `.leftMouseDown` / `.leftMouseUp` |
| Right click | 1 | `.rightMouseDown` / `.rightMouseUp` |
| Middle click | 2 | `.otherMouseDown` / `.otherMouseUp` |
| Side button (Back) | 3 | `.otherMouseDown` / `.otherMouseUp` |
| Side button (Forward) | 4 | `.otherMouseDown` / `.otherMouseUp` |

All buttons beyond left and right are delivered as `otherMouseDown`/`otherMouseUp`. The button number is read from the event's `.mouseEventButtonNumber` field.

### Complete EventTapManager Implementation

```swift
import Cocoa

final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called when a mouse button event is detected.
    /// Parameters: (buttonNumber, isDown)
    /// Return true to swallow the event, false to pass through.
    var onMouseButton: ((_ buttonNumber: Int64, _ isDown: Bool) -> Bool)?

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,         // Active — can swallow events
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        ) else {
            print("[EventTapManager] Failed to create event tap — check Accessibility permission")
            return false
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        CGEvent.tapEnable(tap: tap, enable: true)
        print("[EventTapManager] Event tap active")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            self.runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.eventTap = nil
        }
        print("[EventTapManager] Event tap stopped")
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // Handle tap timeout — macOS disables the tap if callback is slow
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[EventTapManager] Re-enabled tap after \(type)")
            }
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        let isDown = (type == .otherMouseDown)

        let shouldSwallow = onMouseButton?(buttonNumber, isDown) ?? false

        if shouldSwallow {
            return nil  // Event consumed — never reaches any application
        }

        return Unmanaged.passUnretained(event)  // Pass through unchanged
    }

    deinit {
        stop()
    }
}
```

### Critical Memory Management Detail

| Return scenario | Correct call | Why |
|----------------|-------------|-----|
| Same event, unchanged | `Unmanaged.passUnretained(event)` | System already owns +1 ref. `passRetained` would leak. |
| New/copied event | `Unmanaged.passRetained(newEvent)` | Caller releases it, needs +1 ref. |
| Swallow event | `return nil` | System releases the original. |

**Warning:** Many online examples use `passRetained(event)` for the same-event case. This leaks one CGEvent per callback invocation.

### Tap Timeout Handling

macOS disables an event tap if the callback takes longer than ~500ms-1s. The callback receives `type == .tapDisabledByTimeout`. You **must** re-enable:

```swift
if type == .tapDisabledByTimeout {
    if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    return Unmanaged.passUnretained(event)
}
```

**Rule:** Keep the callback fast. No I/O, network calls, or blocking operations. If complex logic is needed, dispatch asynchronously and return immediately.

### Thread Safety

- The callback runs on the thread whose RunLoop the tap source was added to
- Adding to `CFRunLoopGetCurrent()` from `applicationDidFinishLaunching` = main thread
- Main thread is fine for this app — the callback just checks a button number and optionally posts a synthetic event
- All AppKit/UI access from the callback is safe if on main thread

---

## 8. Keyboard Event Synthesis

### Virtual Key Codes (Verified)

| Key | Constant | Hex | Decimal |
|-----|----------|-----|---------|
| O | `kVK_ANSI_O` | `0x1F` | 31 |
| E | `kVK_ANSI_E` | `0x0E` | 14 |

Defined in `Carbon.HIToolbox/Events.h`. Can use raw values to avoid importing Carbon.

### Import Options

**Option A (recommended — no Carbon import):**
```swift
import Cocoa  // CGEvent, CGEventSource, etc. are in CoreGraphics, re-exported by Cocoa

private let kCodeO: CGKeyCode = 0x1F
private let kCodeE: CGKeyCode = 0x0E
```

**Option B (named constants):**
```swift
import Carbon.HIToolbox

private let kCodeO = CGKeyCode(kVK_ANSI_O)  // 0x1F
private let kCodeE = CGKeyCode(kVK_ANSI_E)  // 0x0E
```

### Complete KeySynthesizer

```swift
import Cocoa

enum KeySynthesizer {

    private static let kCodeO: CGKeyCode = 0x1F
    private static let kCodeE: CGKeyCode = 0x0E

    /// Post Ctrl+O
    static func postCtrlO() {
        postKeystroke(keyCode: kCodeO, flags: .maskControl)
    }

    /// Post Ctrl+E
    static func postCtrlE() {
        postKeystroke(keyCode: kCodeE, flags: .maskControl)
    }

    /// Post a synthetic keystroke with optional modifier flags.
    /// Requires Accessibility permission.
    static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            print("[KeySynthesizer] Failed to create CGEvent")
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
```

### Key Details

- **CGEventSource stateID:** Use `.hidSystemState` — events appear as if from physical hardware. Pair with `.cghidEventTap` for posting.
- **Both keyDown and keyUp need the same flags.** Otherwise the modifier state can get stuck.
- **No delay needed** between keyDown and keyUp in most cases. The OS processes them in event queue order.
- **`CGEvent.post()` silently does nothing** without Accessibility permission — it doesn't crash or throw.
- Virtual key codes are **layout-independent** — `0x1F` is always the physical O-position key on US ANSI layout.

---

## 9. Learn Mode

### Design

When the user clicks "Learn Button A", the app enters learn mode:
1. The menu item title changes to "Press the mouse button now..."
2. The next `otherMouseDown` event is captured
3. The button number is saved to `Settings.buttonA`
4. The menu item title updates to show the learned mapping
5. Learn mode exits

### Implementation Approach

```swift
// In AppDelegate:
enum LearnTarget { case a, b }
private var learnTarget: LearnTarget? = nil

@objc private func learnButtonA(_ sender: NSMenuItem) {
    learnTarget = .a
    learnAItem.title = "Press the mouse button now..."
}

@objc private func learnButtonB(_ sender: NSMenuItem) {
    learnTarget = .b
    learnBItem.title = "Press the mouse button now..."
}
```

In the EventTapManager callback (via `onMouseButton`):

```swift
eventTapManager.onMouseButton = { [weak self] buttonNumber, isDown in
    guard let self = self else { return false }

    // Learn mode: capture button on down press
    if isDown, let target = self.learnTarget {
        DispatchQueue.main.async {
            switch target {
            case .a:
                Settings.buttonA = Int(buttonNumber)
            case .b:
                Settings.buttonB = Int(buttonNumber)
            }
            self.learnTarget = nil
            self.refreshMenuTitles()
        }
        return true  // Swallow the learn press
    }

    // Normal mode: check if this button is mapped
    guard Settings.isEnabled else { return false }

    if buttonNumber == Int64(Settings.buttonA ?? -1) {
        if isDown { KeySynthesizer.postCtrlO() }
        return Settings.swallowEvents
    }

    if buttonNumber == Int64(Settings.buttonB ?? -1) {
        if isDown { KeySynthesizer.postCtrlE() }
        return Settings.swallowEvents
    }

    return false  // Unmapped button — pass through
}
```

### Important: Razer Side Buttons May Appear as Keyboard Events

Research found that some Razer mice (without Synapse installed) report side buttons as **keyboard events** rather than mouse events. If the Cobra does this, `otherMouseDown` won't fire for them.

**Recommended enhancement for Learn mode:** Also listen for `keyDown` events in the CGEventTap event mask during learn mode. This way, if the side buttons emit key events instead of mouse events, they'll still be captured. The event mask would be:

```swift
// During learn mode, expand the mask:
let learnMask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue) |
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.keyUp.rawValue)
```

However, this adds complexity. **Start with mouse-only detection first** and only add keyboard event detection if the Cobra's buttons don't appear as mouse events.

---

## 10. Start at Login (Nice-to-Have)

### SMAppService (macOS 13+)

No entitlements, no Info.plist changes, no Xcode capabilities. Just import and call:

```swift
import ServiceManagement

@objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
    if SMAppService.mainApp.status == .enabled {
        try? SMAppService.mainApp.unregister()
    } else {
        try? SMAppService.mainApp.register()
    }
    sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
}
```

### Status Values

| Value | Meaning |
|-------|---------|
| `.enabled` | Registered and active |
| `.notRegistered` | Explicitly unregistered |
| `.notFound` | Service not found |
| `.requiresApproval` | Pending user approval |

**Never cache status locally.** Always read `SMAppService.mainApp.status` fresh — the user can toggle it in System Settings > General > Login Items.

### Menu Item

```swift
let loginItem = NSMenuItem(
    title: "Start at Login",
    action: #selector(toggleStartAtLogin(_:)),
    keyEquivalent: ""
)
loginItem.target = self

// Refresh in menuWillOpen:
loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
```

---

## 11. IOHIDManager Fallback (Only If Needed)

> This section is only relevant if CGEventTap does not capture the Cobra's side buttons. Try CGEventTap first.

### When IOHIDManager Would Be Needed

If the side buttons are vendor-specific HID events that macOS does not translate into standard `otherMouseDown` events, IOHIDManager can read raw HID reports directly.

### Key Limitation

IOHIDManager is **read-only**. Unlike CGEventTap (where returning nil swallows the event), IOHIDManager cannot prevent the original button event from reaching macOS. The "swallow events" feature would not work in fallback mode.

### Permissions

IOHIDManager requires **Input Monitoring** permission (separate from Accessibility).

### Basic Setup

```swift
import IOKit.hid

final class HIDMouseMonitor {
    private var manager: IOHIDManager?

    var onButtonEvent: ((_ usageID: Int, _ pressed: Bool) -> Void)?

    func start() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match mouse devices
        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
        ]
        IOHIDManagerSetDeviceMatching(manager!, matchDict as CFDictionary)

        let callback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let monitor = Unmanaged<HIDMouseMonitor>.fromOpaque(context).takeUnretainedValue()

            let element = IOHIDValueGetElement(value)
            let usagePage = IOHIDElementGetUsagePage(element)

            // Only care about button events (usage page 0x09)
            guard usagePage == kHIDPage_Button else { return }

            let usageID = Int(IOHIDElementGetUsage(element))
            let pressed = IOHIDValueGetIntegerValue(value) != 0

            monitor.onButtonEvent?(usageID, pressed)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager!, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager!, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager!, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        guard let manager = manager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }
}
```

### Integration Strategy (if needed)

Detection order during Learn mode:
1. Listen for `otherMouseDown` via CGEventTap (standard)
2. Listen for `keyDown` via CGEventTap (Razer keyboard-emulation pattern)
3. If neither fires after a timeout → activate IOHIDManager to discover raw HID events
4. Use whichever method detected the button for ongoing operation

---

## 12. Known Gotchas & Edge Cases

### Memory Management
- Use `Unmanaged.passUnretained(event)` when returning the same event from the tap callback. Using `passRetained` leaks memory.
- The `userInfo` pointer for the callback must use `Unmanaged.passUnretained(self).toOpaque()` — the class must stay alive for the lifetime of the tap.

### Tap Timeout
- macOS disables the tap if the callback blocks for ~500ms+
- Always handle `.tapDisabledByTimeout` by re-enabling the tap
- Keep the callback fast — no blocking I/O

### Razer Synapse
- **With Synapse installed:** Side buttons may be remapped to keyboard shortcuts at the driver level, so `otherMouseDown` won't fire
- **Without Synapse:** Standard Razer mice report side buttons as normal `otherMouseDown` with button numbers 3, 4, etc.
- **Recommendation:** Document that users should not have Synapse intercepting button events

### Code Signing During Development
- Each rebuild may create a new code identity, requiring re-granting Accessibility permission
- This is expected during development; release builds with stable signing won't have this issue

### Button Number 0 Ambiguity
- `UserDefaults.integer(forKey:)` returns 0 for absent keys — same as left mouse button number
- Always check `object(forKey:) != nil` before reading optional button numbers

### Event Posting Without Permission
- `CGEvent.post()` silently does nothing without Accessibility permission — no crash, no error
- Always check permission before assuming keystrokes are being delivered

### Virtual Key Codes Are Physical
- `kVK_ANSI_O` (0x1F) refers to the physical key position, not the character
- On non-ANSI layouts, the same physical key may produce a different character
- For Ctrl+O / Ctrl+E this is generally fine since Ctrl shortcuts typically use the physical key

---

## Wiring It All Together (AppDelegate Flow)

```
applicationDidFinishLaunching
  │
  ├─ Settings.registerDefaults()
  ├─ setupStatusItem() + buildMenu()
  │
  └─ PermissionManager.checkAccessibility()
       ├─ Granted
       │    └─ eventTapManager.start()
       │         └─ onMouseButton callback handles learn mode + key synthesis
       └─ Not Granted
            ├─ Show permission alert (if first time)
            └─ Poll every 1s
                 └─ When granted → eventTapManager.start()
```

### Normal Operation (with both buttons learned):

```
Mouse side button pressed (otherMouseDown, button 3)
  └─ EventTapManager callback
       ├─ Learn mode active?
       │    └─ Save button number, exit learn mode, return nil (swallow)
       ├─ Settings.isEnabled?
       │    ├─ buttonNumber == Settings.buttonA?
       │    │    └─ KeySynthesizer.postCtrlO(), return nil if swallow
       │    ├─ buttonNumber == Settings.buttonB?
       │    │    └─ KeySynthesizer.postCtrlE(), return nil if swallow
       │    └─ Unmapped → pass through
       └─ Disabled → pass through
```
