import Cocoa
import os.log
import ServiceManagement

private let log = OSLog(subsystem: "com.rolandtolnay.CobraKey", category: "app")

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var eventTapManager: EventTapManager!

    private var enabledItem: NSMenuItem!
    private var learnAItem: NSMenuItem!
    private var learnBItem: NSMenuItem!
    private var swallowItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private enum LearnTarget { case a, b }
    private var learnTarget: LearnTarget?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        os_log(.error, log: log, "applicationDidFinishLaunching called")
        Settings.registerDefaults()
        setupStatusItem()
        buildMenu()
        eventTapManager = EventTapManager()
        wireEventTap()
        checkPermissionsAndStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Status Item & Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "computermouse",
                accessibilityDescription: "CobraKey"
            )
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Enabled checkbox
        enabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = Settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        // Learn Button A
        learnAItem = NSMenuItem(
            title: learnTitle(for: .a),
            action: #selector(learnButtonA(_:)),
            keyEquivalent: ""
        )
        learnAItem.target = self
        menu.addItem(learnAItem)

        // Learn Button B
        learnBItem = NSMenuItem(
            title: learnTitle(for: .b),
            action: #selector(learnButtonB(_:)),
            keyEquivalent: ""
        )
        learnBItem.target = self
        menu.addItem(learnBItem)

        menu.addItem(.separator())

        // Swallow Events checkbox
        swallowItem = NSMenuItem(
            title: "Swallow Events",
            action: #selector(toggleSwallow(_:)),
            keyEquivalent: ""
        )
        swallowItem.target = self
        swallowItem.state = Settings.swallowEvents ? .on : .off
        menu.addItem(swallowItem)

        // Start at Login checkbox
        loginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleStartAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit CobraKey",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        Settings.isEnabled.toggle()
        sender.state = Settings.isEnabled ? .on : .off
    }

    @objc private func learnButtonA(_ sender: NSMenuItem) {
        learnTarget = .a
        learnAItem.title = "Press the mouse button now..."
    }

    @objc private func learnButtonB(_ sender: NSMenuItem) {
        learnTarget = .b
        learnBItem.title = "Press the mouse button now..."
    }

    @objc private func toggleSwallow(_ sender: NSMenuItem) {
        Settings.swallowEvents.toggle()
        sender.state = Settings.swallowEvents ? .on : .off
    }

    @objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            os_log(
                .error,
                log: log,
                "Failed to toggle start-at-login: %{public}@",
                String(describing: error)
            )
            showErrorAlert(
                title: "Start at Login Failed",
                message: error.localizedDescription
            )
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Learn Title Helper

    private enum MappedButton { case a, b }

    private func learnTitle(for button: MappedButton) -> String {
        let label = button == .a ? "A" : "B"
        let shortcut = button == .a ? "Ctrl+O" : "Ctrl+E"
        let num: Int?
        switch button {
        case .a: num = Settings.buttonA
        case .b: num = Settings.buttonB
        }
        if let num {
            return "Learn Button \(label) (button \(num) \u{2192} \(shortcut))"
        }
        return "Learn Button \(label)..."
    }

    // MARK: - Event Tap Wiring

    private func wireEventTap() {
        eventTapManager.onMouseButton = { [weak self] buttonNumber, isDown in
            guard let self else { return false }

            // Learn mode: capture button on down press
            if isDown, let target = self.learnTarget {
                // Clear learn target immediately to avoid capturing rapid extra clicks.
                self.learnTarget = nil
                let learnedButton = Int(buttonNumber)

                switch target {
                case .a:
                    Settings.buttonA = learnedButton
                    if Settings.buttonB == learnedButton {
                        Settings.buttonB = nil
                    }
                case .b:
                    Settings.buttonB = learnedButton
                    if Settings.buttonA == learnedButton {
                        Settings.buttonA = nil
                    }
                }

                self.learnAItem.title = self.learnTitle(for: .a)
                self.learnBItem.title = self.learnTitle(for: .b)
                return true // Swallow the learn press
            }

            // Normal mode
            guard Settings.isEnabled else { return false }

            if buttonNumber == Int64(Settings.buttonA ?? -1) {
                if isDown { KeySynthesizer.postCtrlO() }
                return Settings.swallowEvents
            }

            if buttonNumber == Int64(Settings.buttonB ?? -1) {
                if isDown { KeySynthesizer.postCtrlE() }
                return Settings.swallowEvents
            }

            return false
        }
    }

    // MARK: - Permission Flow

    private func checkPermissionsAndStart() {
        let granted = PermissionManager.isAccessibilityGranted()
        os_log(.error, log: log, "Accessibility granted: %{public}@", granted ? "YES" : "NO")
        os_log(.error, log: log, "hasShownPermissionHelp: %{public}@", Settings.hasShownPermissionHelp ? "YES" : "NO")

        if granted {
            startEventTap()
        } else {
            if !Settings.hasShownPermissionHelp {
                os_log(.error, log: log, "Showing permission alert")
                PermissionManager.showPermissionAlert()
            } else {
                os_log(.error, log: log, "Skipping alert (already shown)")
            }
            PermissionManager.startPollingForPermission { [weak self] in
                os_log(.error, log: log, "Permission granted via polling, starting event tap")
                self?.startEventTap()
            }
        }
    }

    private func startEventTap() {
        let success = eventTapManager.start()
        os_log(.error, log: log, "Event tap start result: %{public}@", success ? "SUCCESS" : "FAILED")
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        enabledItem.state = Settings.isEnabled ? .on : .off
        swallowItem.state = Settings.swallowEvents ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        if learnTarget == nil {
            learnAItem.title = learnTitle(for: .a)
            learnBItem.title = learnTitle(for: .b)
        }
    }
}
