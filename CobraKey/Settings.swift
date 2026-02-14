import Foundation

enum Settings {
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let buttonA = "buttonA"
        static let buttonB = "buttonB"
        static let swallowEvents = "swallowEvents"
        static let hasShownPermissionHelp = "hasShownPermissionHelp"
    }

    /// Call once in applicationDidFinishLaunching
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.isEnabled: true,
            Keys.buttonA: 5,
            Keys.buttonB: 4,
            Keys.swallowEvents: true,
            Keys.hasShownPermissionHelp: false,
        ])
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

    // MARK: - Optional Int properties

    static var buttonA: Int? {
        get {
            guard UserDefaults.standard.object(forKey: Keys.buttonA) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: Keys.buttonA)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Keys.buttonA)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.buttonA)
            }
        }
    }

    static var buttonB: Int? {
        get {
            guard UserDefaults.standard.object(forKey: Keys.buttonB) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: Keys.buttonB)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Keys.buttonB)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.buttonB)
            }
        }
    }
}
