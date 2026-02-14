# CGEventTap — Mouse Button Capture

## Mouse Button Numbering on macOS

macOS uses zero-indexed button numbers reported via the `kCGMouseEventButtonNumber` field (Swift: `.mouseEventButtonNumber`):

| Button | Number | CGEvent Type |
|--------|--------|-------------|
| Left click | 0 (`kCGMouseButtonLeft`) | `.leftMouseDown` / `.leftMouseUp` |
| Right click | 1 (`kCGMouseButtonRight`) | `.rightMouseDown` / `.rightMouseUp` |
| Middle click | 2 (`kCGMouseButtonCenter`) | `.otherMouseDown` / `.otherMouseUp` |
| Side button (Back/Button4) | 3 | `.otherMouseDown` / `.otherMouseUp` |
| Side button (Forward/Button5) | 4 | `.otherMouseDown` / `.otherMouseUp` |

All buttons beyond left (0) and right (1) are delivered as `otherMouseDown`/`otherMouseUp`. The button number distinguishes them. macOS theoretically supports up to 32 mouse buttons.

## CGEventTapLocation Options

| Location | Description |
|----------|-------------|
| `.cghidEventTap` | Lowest level, captures raw HID events before the window server processes them |
| `.cgSessionEventTap` | Session level, after user session starts but before app delivery |
| `.cgAnnotatedSessionEventTap` | Annotated with extra metadata |

`.cgSessionEventTap` is the practical choice for a standard (non-root) app. It does not require root and still allows event swallowing. This is sufficient for a mouse remapper.

## Event Tap Options

| Option | Behavior |
|--------|----------|
| `.defaultTap` | Active filter — callback can modify or swallow events by returning nil |
| `.listenOnly` | Passive — can observe but cannot modify or swallow events |

An active tap (`.defaultTap`) is required for swallowing mouse button events.

## CGEventMask Construction

```swift
let eventMask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)
```

Constructed by bit-shifting 1 by each event type's raw value and OR-ing them together.

## Event Tap Creation

```swift
CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: userInfo
)
```

- Returns `CFMachPort?` — returns **nil** if permission is not granted (does not crash)
- The callback must be a C-compatible function pointer (no closures with captures)
- `userInfo` is an `UnsafeMutableRawPointer?` used to pass context (typically `self`) into the callback
- Use `Unmanaged.passUnretained(self).toOpaque()` for userInfo, and `Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()` to recover inside the callback

## RunLoop Integration

After creating the tap, it must be added to a RunLoop to receive events:

```swift
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
```

The callback executes on the thread whose RunLoop the source was added to. Adding from `applicationDidFinishLaunching` means the main thread, which is fine for lightweight callbacks and allows direct AppKit access.

## Reading Button Numbers

```swift
let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
// Returns Int64: 0=left, 1=right, 2=middle, 3=side-back, 4=side-forward
```

## Swallowing Events

Return `nil` from the callback to consume the event — it never reaches any application:

```swift
return nil  // Event swallowed
```

Return the event to pass it through:

```swift
return Unmanaged.passUnretained(event)  // Event passed through
```

## Memory Management in the Callback

| Scenario | Correct Return | Reason |
|----------|---------------|--------|
| Same event, unchanged | `Unmanaged.passUnretained(event)` | System already owns +1 ref. `passRetained` would leak. |
| New/copied event | `Unmanaged.passRetained(newEvent)` | Caller releases it, so it needs +1 ref. |
| Swallow event | `return nil` | System releases the original. |

**Warning:** Many online examples use `passRetained(event)` for the same-event case. This leaks one `CGEvent` per callback invocation. Always use `passUnretained` when returning the original event.

## Tap Timeout Handling

macOS disables an event tap if the callback takes longer than ~500ms-1s. When this happens, the callback receives a special event with `type == .tapDisabledByTimeout`. The tap must be re-enabled:

```swift
if type == .tapDisabledByTimeout {
    CGEvent.tapEnable(tap: tap, enable: true)
    return Unmanaged.passUnretained(event)
}
```

There is also `.tapDisabledByUserInput` which should be handled the same way.

**Rule:** Keep the callback as fast as possible. No I/O, network calls, or blocking operations. Dispatch complex work asynchronously if needed.

## Stopping the Tap

```swift
CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: false)
```

Setting the `CFMachPort` reference to nil releases it.
