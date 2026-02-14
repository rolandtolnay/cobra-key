import Cocoa

final class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastUserInputReenableAttempt: CFAbsoluteTime = 0

    /// Called when a mouse button event is detected.
    /// Parameters: (buttonNumber, isDown)
    /// Return true to swallow the event, false to pass through.
    var onMouseButton: ((_ buttonNumber: Int64, _ isDown: Bool) -> Bool)?

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        // Handle timeout disables immediately.
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[EventTapManager] Re-enabled tap after \(type)")
            }
            return Unmanaged.passUnretained(event)
        }

        // Some environments can repeatedly emit this disable event.
        // Re-enable with throttling to avoid tight disable/enable loops.
        if type == .tapDisabledByUserInput {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastUserInputReenableAttempt > 2.0 {
                lastUserInputReenableAttempt = now
                if let tap = eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    print("[EventTapManager] Re-enabled tap after user-input disable")
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        let isDown = (type == .otherMouseDown)

        let shouldSwallow = onMouseButton?(buttonNumber, isDown) ?? false

        if shouldSwallow {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}
