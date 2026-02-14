import ApplicationServices
import Cocoa

enum PermissionManager {

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
    }

    static func promptAccessibility() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }

    static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            CobraKey needs Accessibility access to detect mouse button presses \
            and send keyboard shortcuts.

            Please enable CobraKey in:
            System Settings \u{2192} Privacy & Security \u{2192} Accessibility
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            promptAccessibility()
            Settings.hasShownPermissionHelp = true
        }
    }

    private static var permissionTimer: Timer?

    static func startPollingForPermission(onGranted: @escaping () -> Void) {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isAccessibilityGranted() {
                permissionTimer?.invalidate()
                permissionTimer = nil
                onGranted()
            }
        }
    }
}
