# Menubar App — NSStatusItem & AppKit Patterns

## Hiding the Dock Icon

**Info.plist method (standard):**
```xml
<key>LSUIElement</key>
<true/>
```
In Xcode GUI: target → Info → add `Application is agent (UIElement)` = `YES`.

**Programmatic alternative:**
```swift
NSApplication.shared.setActivationPolicy(.accessory)
```

Both hide the app from the Dock and Cmd+Tab switcher. The Info.plist method is preferred for a menubar-only app.

## No XIB/Storyboard Needed

Everything can be done programmatically. Delete `MainMenu.xib` if Xcode generates one. Remove the `NSMainNibFile` / `NSMainStoryboardFile` key from Info.plist if present.

## Entry Point Options

**Option A — `@main` on AppDelegate (simplest, recommended for pure AppKit):**
```swift
@main
class AppDelegate: NSObject, NSApplicationDelegate { ... }
```
No separate `App.swift` or `main.swift` needed.

**Option B — SwiftUI wrapper with `@NSApplicationDelegateAdaptor`:**
```swift
@main
struct MenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { } }
}
```
Only ONE file can have `@main`. If using this, remove `@main` from AppDelegate.

**Option C — Explicit `main.swift`:**
```swift
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```
Neither `@main` nor `@NSApplicationMain` is used with this approach.

## NSStatusItem Creation

```swift
// Variable width — auto-sizes to content
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

// Fixed width
statusItem = NSStatusBar.system.statusItem(withLength: 28.0)
```

Key properties:
- `statusItem.menu` — assign an NSMenu to show on click
- `statusItem.button` — the NSStatusBarButton for image/title
- `statusItem.button?.image` — the icon
- `statusItem.button?.title` — text (can combine with image)
- `statusItem.isVisible` — show/hide

## Setting the Menubar Icon

**SF Symbols (macOS 11+, recommended):**
```swift
statusItem.button?.image = NSImage(
    systemSymbolName: "keyboard",
    accessibilityDescription: "CobraKey"
)
```

Good SF Symbols for menubar (simple, legible at small size):
- `keyboard` — keyboard-related
- `cursorarrow.click` — mouse/click
- `command` — keyboard shortcuts
- `bolt` — quick action
- `gearshape` — settings/utility

**Custom image:**
```swift
let image = NSImage(named: "MenuBarIcon")
image?.isTemplate = true  // CRITICAL: adapts to light/dark mode
statusItem.button?.image = image
```

For custom images: 16x16pt (32x32px @2x) PNG. `isTemplate = true` is required for proper light/dark mode adaptation. SF Symbols handle this automatically.

## NSMenu Construction

```swift
let menu = NSMenu()

// Regular action item
let item = NSMenuItem(title: "Do Something", action: #selector(doSomething), keyEquivalent: "")
item.target = self  // IMPORTANT: always set target for AppDelegate methods
menu.addItem(item)

// Separator
menu.addItem(NSMenuItem.separator())

// Checkbox item (toggle via .state)
let checkItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
checkItem.target = self
checkItem.state = .off   // .on = checkmark, .off = none, .mixed = dash
menu.addItem(checkItem)

// Disabled info/label item
let infoItem = NSMenuItem(title: "Status: idle", action: nil, keyEquivalent: "")
infoItem.isEnabled = false
menu.addItem(infoItem)

// Quit (targets NSApplication directly, no explicit target needed)
let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(quitItem)

// Assign to status item
statusItem.menu = menu
```

**Critical:** Always set `.target = self` on menu items whose actions are defined in AppDelegate. Without it, the action won't route correctly and the item appears grayed out.

## Dynamic Menu Item Updates

**Approach A — Hold references and mutate directly:**
```swift
private var learnItem: NSMenuItem!

// Later:
learnItem.title = "Press the mouse button now..."
learnItem.state = .on
```

**Approach B — NSMenuDelegate for lazy refresh:**
```swift
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update items right before menu is shown
        enabledItem.state = isEnabled ? .on : .off
    }
}
// Set delegate: menu.delegate = self
```

`menuWillOpen` is useful for ensuring menu state is always current when the user clicks the menubar icon.

## App Lifecycle Methods

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // Setup status item and menu here
}

func applicationWillTerminate(_ notification: Notification) {
    // Cleanup: save state, stop event taps
}

func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false  // Keep running with no windows
}

func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true  // Required for modern macOS
}
```

Since there is no main window, the app runs until explicitly quit from the menu.
