import Cocoa

enum Settings {
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let swallowEvents = "swallowEvents"
        static let hasShownPermissionHelp = "hasShownPermissionHelp"
        static let mappings = "mappings"

        // Legacy keys (used only during migration)
        static let buttonA = "buttonA"
        static let buttonB = "buttonB"
    }

    /// Call once in applicationDidFinishLaunching
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.isEnabled: true,
            Keys.swallowEvents: true,
            Keys.hasShownPermissionHelp: false,
        ])
    }

    /// Converts old buttonA/buttonB settings to ButtonMapping entries.
    /// Safe to call multiple times; only migrates if legacy keys exist.
    static func migrateIfNeeded() {
        let ud = UserDefaults.standard
        let hasA = ud.object(forKey: Keys.buttonA) != nil
        let hasB = ud.object(forKey: Keys.buttonB) != nil
        guard hasA || hasB else { return }

        var migrated: [ButtonMapping] = []

        if hasA {
            let button = ud.integer(forKey: Keys.buttonA)
            migrated.append(ButtonMapping(
                id: UUID(),
                mouseButton: button,
                keyCode: 0x1F,    // O
                modifierFlags: CGEventFlags.maskControl.rawValue
            ))
        }

        if hasB {
            let button = ud.integer(forKey: Keys.buttonB)
            // Avoid duplicate if both were mapped to the same mouse button
            if !migrated.contains(where: { $0.mouseButton == button }) {
                migrated.append(ButtonMapping(
                    id: UUID(),
                    mouseButton: button,
                    keyCode: 0x0E,    // E
                    modifierFlags: CGEventFlags.maskControl.rawValue
                ))
            }
        }

        // Write migrated mappings and remove legacy keys
        mappings = migrated
        ud.removeObject(forKey: Keys.buttonA)
        ud.removeObject(forKey: Keys.buttonB)
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

    // MARK: - Mappings

    static var mappings: [ButtonMapping] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.mappings) else {
                return []
            }
            return (try? JSONDecoder().decode([ButtonMapping].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: Keys.mappings)
        }
    }
}
