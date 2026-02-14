import Cocoa
import os.log
import ServiceManagement

private let log = OSLog(subsystem: "com.rolandtolnay.CobraKey", category: "app")

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var eventTapManager: EventTapManager!

    private var enabledItem: NSMenuItem!
    private var addMappingItem: NSMenuItem!
    private var swallowItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var recorderPanel: ShortcutRecorderPanel?
    private var cachedMappings: [ButtonMapping] = []

    private static let mappingTagBase = 1000

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        os_log(.info, log: log, "applicationDidFinishLaunching called")
        Settings.registerDefaults()
        Settings.migrateIfNeeded()
        reloadMappings()
        setupStatusItem()
        buildMenu()
        eventTapManager = EventTapManager()
        wireEventTap()
        checkPermissionsAndStart()
        updateStatusIcon()
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

    // MARK: - Mappings Cache

    private func reloadMappings() {
        cachedMappings = Settings.mappings
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

    private func updateStatusIcon() {
        statusItem.button?.appearsDisabled = !Settings.isEnabled
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Version label
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versionItem = NSMenuItem(title: "CobraKey v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

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

        // Add Mapping... (sentinel tag -1)
        addMappingItem = NSMenuItem(
            title: "Add Mapping...",
            action: #selector(addMapping(_:)),
            keyEquivalent: ""
        )
        addMappingItem.target = self
        addMappingItem.tag = -1
        menu.addItem(addMappingItem)

        menu.addItem(.separator())

        // Block Original Click checkbox
        swallowItem = NSMenuItem(
            title: "Block Original Click",
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
        updateStatusIcon()
    }

    @objc private func addMapping(_ sender: NSMenuItem) {
        recorderPanel?.close()
        let panel = ShortcutRecorderPanel()
        panel.recorderDelegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel = panel
    }

    @objc private func mappingClicked(_ sender: NSMenuItem) {
        let index = sender.tag - Self.mappingTagBase
        guard index >= 0, index < cachedMappings.count else { return }

        let mapping = cachedMappings[index]

        let alert = NSAlert()
        alert.messageText = "Delete Mapping?"
        alert.informativeText = "Remove \"\(mapping.displayTitle)\"?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var all = Settings.mappings
        all.removeAll { $0.id == mapping.id }
        Settings.mappings = all
        reloadMappings()
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

    // MARK: - Event Tap Wiring

    private func wireEventTap() {
        eventTapManager.onMouseButton = { [weak self] buttonNumber, isDown in
            guard let self else { return false }

            // Recorder mode: route mouse button to the active panel
            if isDown, let panel = self.recorderPanel, panel.isWaitingForMouseButton {
                panel.didCaptureMouseButton(Int(buttonNumber))
                return true // Swallow the capture press
            }

            // Recorder mode: swallow mouse-up for the button being recorded
            if !isDown, let panel = self.recorderPanel,
               panel.capturedMouseButton == Int(buttonNumber) {
                return true
            }

            // Normal mode
            guard Settings.isEnabled else { return false }

            let button = Int(buttonNumber)
            guard let mapping = self.cachedMappings.first(where: { $0.mouseButton == button }) else {
                return false
            }

            if isDown {
                KeySynthesizer.postKeystroke(
                    keyCode: CGKeyCode(mapping.keyCode),
                    flags: CGEventFlags(rawValue: mapping.modifierFlags)
                )
            }
            return Settings.swallowEvents
        }
    }

    // MARK: - Permission Flow

    private func checkPermissionsAndStart() {
        let granted = PermissionManager.isAccessibilityGranted()
        os_log(.error, log: log, "Accessibility granted: %{public}@", granted ? "YES" : "NO")

        if granted {
            startEventTap()
        } else {
            if !Settings.hasShownPermissionHelp {
                os_log(.info, log: log, "Showing permission alert")
                PermissionManager.showPermissionAlert()
            } else {
                os_log(.info, log: log, "Prompting accessibility (already shown help)")
                PermissionManager.promptAccessibility()
            }
            PermissionManager.startPollingForPermission { [weak self] in
                os_log(.info, log: log, "Permission granted via polling, starting event tap")
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

        // Remove stale dynamic mapping items
        let staleItems = menu.items.filter { $0.tag >= Self.mappingTagBase }
        for item in staleItems {
            menu.removeItem(item)
        }

        // Insert current mappings before "Add Mapping..." item
        reloadMappings()
        guard let addIndex = menu.items.firstIndex(where: { $0.tag == -1 }) else { return }

        for (i, mapping) in cachedMappings.enumerated() {
            let item = NSMenuItem(
                title: mapping.displayTitle,
                action: #selector(mappingClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Self.mappingTagBase + i
            menu.insertItem(item, at: addIndex + i)
        }
    }
}

// MARK: - ShortcutRecorderDelegate

extension AppDelegate: ShortcutRecorderDelegate {
    func shortcutRecorder(_ panel: ShortcutRecorderPanel, didRecord mapping: ButtonMapping) {
        recorderPanel = nil

        var all = Settings.mappings

        // Check for duplicate mouse button
        if let existingIndex = all.firstIndex(where: { $0.mouseButton == mapping.mouseButton }) {
            let existing = all[existingIndex]
            let alert = NSAlert()
            alert.messageText = "Replace Existing Mapping?"
            alert.informativeText = "Button \(mapping.mouseButton) is already mapped to \"\(existing.displayTitle)\". Replace it?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            all.remove(at: existingIndex)
        }

        all.append(mapping)
        Settings.mappings = all
        reloadMappings()
    }

    func shortcutRecorderDidCancel(_ panel: ShortcutRecorderPanel) {
        recorderPanel = nil
    }
}
