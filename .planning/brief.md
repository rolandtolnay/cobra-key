## Project Brief: “CobraKey” (Minimal macOS mouse-button → keybind mapper)

### Goal

Build a tiny macOS **menubar (status bar) app** that maps the **two side buttons** on a **Razer Cobra mouse** to keyboard shortcuts:

* Side Button A → **Control + O**
* Side Button B → **Control + E**

The app should run quietly in the background, consume almost no resources, and avoid any “suite” features (no profiles, macros, analytics, cloud sync, etc.).

### Why

Razer’s official macOS app doesn’t support this specific device model, and existing tools are overkill/bloated for this single mapping.

---

## Scope

### In scope (must have)

1. **Global mouse event capture**

   * Detect presses of the two side buttons system-wide.
2. **Key event injection**

   * Emit synthetic keystrokes for Ctrl+O and Ctrl+E.
3. **Menubar UI (minimal)**

   * A status bar icon with a tiny menu:

     * Enabled toggle (On/Off)
     * “Learn Button A” (capture next mouse button press → assign)
     * “Learn Button B”
     * Quit
4. **Persistence**

   * Save learned button numbers + enabled state using `UserDefaults`.
5. **Permissions handling**

   * Detect and prompt for the needed macOS permissions (Accessibility; possibly Input Monitoring depending on OS behavior).
   * If permissions are missing, show a clear instruction dialog that links user to the right System Settings screen.

### Nice-to-have (only if cheap)

* “Start at Login” toggle (SMAppService / ServiceManagement).
* Optional “Swallow original mouse button” toggle (default: swallow).

### Out of scope (explicitly avoid)

* Complex remapping UI, multiple profiles, per-app mappings, macros, gestures, scroll tuning, acceleration tuning.
* External dependencies (no third-party frameworks).
* Installer, notarization, auto-update.

---

## Assumptions / Reality Checks

* **Best-case:** macOS exposes the Cobra side buttons as standard “other mouse buttons” (commonly button numbers 3 and 4, i.e., “Button 4/5” in many apps).
* **If not:** the buttons may be vendor/HID-specific and not appear via normal event taps. In that case, the app should still support a “Learn” mode to detect what macOS provides. If *nothing* arrives via the event tap, document that as a limitation and optionally add an IOHIDManager fallback (only if needed).

---

## Technical Approach

### Platform & language

* macOS AppKit menubar app in **Swift** (Xcode project).
* Background-only feel:

  * Hide Dock icon using `LSUIElement = true` in `Info.plist`.
  * Use an `NSStatusItem` icon + menu.

### Core mechanics

1. **Event Tap for mouse button events**

   * Install a CGEventTap (likely `cghidEventTap`) listening to:

     * `otherMouseDown`, `otherMouseUp` (and optionally `otherMouseDragged`)
   * Read `kCGMouseEventButtonNumber` to identify which mouse button triggered the event.
2. **Mapping**

   * Two configurable integer button numbers: `buttonA`, `buttonB`
   * Default values can be nil until learned, or set defaults (3 and 4) and allow override via Learn.
3. **Synthesizing keyboard shortcuts**

   * Post keydown+keyup events with control modifier:

     * Ctrl+O and Ctrl+E
   * Use reliable virtual key codes (Carbon HIToolbox constants).
4. **Swallowing**

   * If enabled and a mapped button is pressed, return `nil` from callback to prevent the original mouse event from reaching apps.
5. **Robustness**

   * Event taps can be disabled if the callback is slow. Handle `tapDisabledByTimeout` / `tapDisabledByUserInput` by re-enabling the tap and logging.

---

## Permissions & UX Requirements

### Permissions

* Accessibility permission is typically required to **post** synthetic events to other apps.
* Depending on macOS version/settings, the app may also need **Input Monitoring** to reliably read global input events.

### UX rules

* On first run (or when missing permissions):

  * Show a single clear dialog:

    * What permission is needed
    * Why (to map mouse buttons to keyboard shortcuts)
    * A button to open the relevant System Settings page (or at least open System Settings and provide step-by-step text)
* Do **not** spam prompts; store a “hasShownPermissionHelp” flag.

---

## Menubar UI Spec (very small)

Status menu items:

1. **Enabled** (checkbox)
2. Separator
3. **Learn Button A…**

   * After click: menu item changes to “Press the mouse button now…”
   * Next detected `otherMouseDown` sets `buttonA` and shows a brief confirmation (small alert or menu item subtitle).
4. **Learn Button B…**
5. Separator
6. **Quit**

Optional debug item (can be behind a build flag):

* “Show current mapping: A=3, B=4”

No settings window unless absolutely necessary.

---

## Data Model (UserDefaults keys)

* `isEnabled: Bool` (default true)
* `buttonA: Int` (optional)
* `buttonB: Int` (optional)
* `swallowEvents: Bool` (default true)
* `hasShownPermissionHelp: Bool` (default false)

---

## Acceptance Criteria (definition of done)

1. When the app is **enabled**, pressing side button A triggers **Ctrl+O** in the active app.
2. Pressing side button B triggers **Ctrl+E** in the active app.
3. App runs with **no Dock icon**, only a menubar icon.
4. Button mapping can be configured via **Learn** and persists across restarts.
5. If permissions are missing, user receives clear instructions and the app fails gracefully (doesn’t crash).
6. CPU usage stays near zero when idle.

---

## Testing Plan

Manual tests:

* Verify in:

  * TextEdit: Ctrl+O opens file picker; Ctrl+E does expected behavior (or map to something testable).
  * Browser address bar / any editor
* Verify swallow behavior:

  * If swallow is on, side buttons should not trigger “Back/Forward” in browsers (if they otherwise would).
* Verify learn mode:

  * Clicking Learn A then pressing the physical side button assigns correctly.
* Verify restart persistence:

  * Quit app → reopen → mapping still works.

---

## Deliverables

* Xcode project (Swift, AppKit).
* Source code with clear structure:

  * `AppDelegate` / `StatusBarController`
  * `EventTapManager`
  * `KeySynthesizer`
  * `Preferences`
* README with:

  * How to build/run locally
  * How to grant permissions
  * Known limitations (especially if buttons don’t surface via CGEventTap)

---

## Implementation Notes (guardrails for the agent)

* Keep it small and readable; avoid abstractions unless needed.
* No third-party libs.
* Prioritize “works reliably” over “fancy UI”.
* If CGEventTap doesn’t see any side-button events:

  * Add logging mode (“print all button numbers seen”)
  * If still nothing, document it and propose an IOHIDManager fallback **as a separate optional step**, not mandatory.