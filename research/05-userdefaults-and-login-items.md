# UserDefaults & SMAppService Login Items

## UserDefaults in AppKit (Not SwiftUI)

`@AppStorage` is a SwiftUI property wrapper. In a pure AppKit app, use `UserDefaults.standard` directly.

### Registering Default Values

Call `register(defaults:)` once at app launch. These are in-memory fallbacks — they do not persist to disk and do not overwrite values the user has already set.

```swift
UserDefaults.standard.register(defaults: [
    "isEnabled": true,
    "swallowEvents": true,
    "hasShownPermissionHelp": false
])
```

Optional values (button numbers that may be nil) should NOT be registered — their default is "absent," which is already the natural state when the key doesn't exist.

### Storing Optional Int Values

`UserDefaults.integer(forKey:)` returns `0` when the key is absent — it cannot distinguish "not set" from "set to 0." For optional integers:

**Reading:**
```swift
guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
return UserDefaults.standard.integer(forKey: key)
```

**Writing:**
```swift
UserDefaults.standard.set(42, forKey: "buttonA")      // Set value
UserDefaults.standard.removeObject(forKey: "buttonA")  // Clear to nil
```

### Observing Changes

**Broad (any key changed):**
```swift
NotificationCenter.default.addObserver(
    forName: UserDefaults.didChangeNotification,
    object: nil, queue: .main
) { _ in
    // React to any settings change
}
```

**Specific key (KVO):**
```swift
private var observation: NSKeyValueObservation?

observation = UserDefaults.standard.observe(\.isEnabled, options: [.new]) { _, change in
    // React to specific change
}
```
Note: KVO on UserDefaults requires the key to be exposed as `@objc dynamic` on an extension, or use string-based KVO.

### Custom Property Wrappers

**For non-optional values:**
```swift
@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
```

**For optional values:**
```swift
@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String

    var wrappedValue: T? {
        get { UserDefaults.standard.object(forKey: key) as? T }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}
```

### Key Prefixing

Not needed. UserDefaults is already sandboxed to the app's bundle identifier.

---

## SMAppService — Start at Login (macOS 13+)

Replaces the deprecated `SMLoginItemSetEnabled` (macOS 10.11) and `LSSharedFileList`.

### Requirements

- **Import:** `ServiceManagement`
- **Entitlements:** None needed
- **Info.plist:** No changes needed
- **Xcode capabilities:** None needed

Just import and call the API.

### Registration

```swift
import ServiceManagement

try SMAppService.mainApp.register()    // Enable start at login
try SMAppService.mainApp.unregister()  // Disable start at login
```

When registered, macOS shows a system notification to the user confirming the login item was added.

### Status Property

`SMAppService.mainApp.status` returns:

| Value | Meaning |
|-------|---------|
| `.enabled` | Registered and active |
| `.notRegistered` | Explicitly unregistered |
| `.notFound` | Service not found |
| `.requiresApproval` | Pending user approval in System Settings |

### Never Cache Status Locally

Always read `SMAppService.mainApp.status` fresh. The user can toggle the login item in System Settings > General > Login Items at any time, so a UserDefaults cache would go stale.

### Toggling from a Menu Item

```swift
@objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    if SMAppService.mainApp.status == .enabled {
        try? SMAppService.mainApp.unregister()
    } else {
        try? SMAppService.mainApp.register()
    }
    sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
}
```

Refresh the checkmark in `menuWillOpen` by re-reading status:
```swift
loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
```
