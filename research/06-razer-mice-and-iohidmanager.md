# Razer Mice on macOS & IOHIDManager Fallback

## Razer Side Button Behavior on macOS

### Without Razer Synapse Installed

Standard Razer mice (DeathAdder, Viper, Cobra) report their side buttons as normal `otherMouseDown`/`otherMouseUp` events with button numbers 3, 4, etc. They behave like any standard USB HID-compliant mouse. CGEventTap will see them.

### With Razer Synapse Installed

Synapse can intercept side buttons at the driver level and remap them to **keyboard events**. In this case:
- Side buttons will NOT appear as `otherMouseDown` events
- They appear as `keyDown`/`keyUp` events instead
- A CGEventTap listening only for `otherMouseDown` will never see them

### Razer Naga (Many-Button Mice)

The Naga's side grid buttons are particularly affected by Synapse. With Synapse, they map to numpad keys by default. Without Synapse, they may report as `otherMouseDown` with sequential button numbers (3, 4, 5, ..., up to 14).

### Community Reports

A Razer Naga V2 Hyperspeed user reported that side buttons are "basically just keyboard keys in the eyes of macOS." Tools like Karabiner Elements, BetterTouchTool, and USB Overdrive X all successfully handle Razer side buttons — confirming they produce some form of detectable input on macOS.

### Recommendation

- Instruct users to uninstall or disable Razer Synapse for best results
- During learn mode, also listen for `keyDown` events in case buttons report as keyboard input
- Only pursue IOHIDManager if both `otherMouseDown` and `keyDown` detection fail

---

## IOHIDManager — Low-Level HID Access

IOHIDManager reads raw HID reports directly from USB/Bluetooth devices. It can capture button events that macOS doesn't translate into standard Quartz events.

### When It Would Be Needed

Only if the Cobra's side buttons are vendor-specific HID events that macOS does not surface as either `otherMouseDown` or `keyDown` events through CGEventTap.

### Key Limitation: No Event Swallowing

IOHIDManager is **read-only** at the HID layer. Unlike CGEventTap (where returning nil swallows the event), IOHIDManager cannot prevent the original button event from reaching macOS. The "swallow events" feature would not work in this fallback mode.

### Permissions

IOHIDManager requires **Input Monitoring** permission (separate from Accessibility). If the app already has Accessibility for CGEventTap, an additional permission grant would be needed.

### Device Matching

```swift
let matchDict: [String: Any] = [
    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,   // 0x01
    kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse             // 0x02
]
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
```

To filter specifically for Razer devices, add vendor ID matching:
```swift
// Razer vendor ID: 0x1532
matchDict[kIOHIDVendorIDKey] = 0x1532
```

### Button Events in HID Reports

Button events are on usage page `kHIDPage_Button` (0x09). Usage IDs correspond to button numbers:
- Usage 1 = Button 1 (left click)
- Usage 2 = Button 2 (right click)
- Usage 3 = Button 3 (middle click)
- Usage 4 = Button 4 (side back)
- Usage 5 = Button 5 (side forward)

Filter the input value callback to `usagePage == kHIDPage_Button` to avoid noise from X/Y axis and scroll wheel data.

### Basic Setup

```swift
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

let callback: IOHIDValueCallback = { context, result, sender, value in
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)

    guard usagePage == kHIDPage_Button else { return }

    let usageID = Int(IOHIDElementGetUsage(element))
    let pressed = IOHIDValueGetIntegerValue(value) != 0
    // usageID is the button number, pressed is the state
}

IOHIDManagerRegisterInputValueCallback(manager, callback, context)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
```

### Practical Detection Strategy (if CGEventTap fails)

1. Listen for `otherMouseDown` via CGEventTap (standard mouse buttons)
2. Listen for `keyDown` via CGEventTap (Razer keyboard-emulation pattern)
3. If neither fires after a timeout → activate IOHIDManager to discover raw HID events
4. Use whichever method detected the button for ongoing operation
