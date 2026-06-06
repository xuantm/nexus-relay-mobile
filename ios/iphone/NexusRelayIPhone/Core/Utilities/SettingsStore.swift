import Foundation

protocol SettingsStore: AnyObject {
    var settings: AppSettings { get set }
}

final class UserDefaultsSettingsStore: SettingsStore {
    private let userDefaults: UserDefaults
    private let key = "com.nexusrelay.iphone.settings"

    var settings: AppSettings {
        get {
            guard let data = userDefaults.data(forKey: key) else {
                return .defaults
            }
            return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .defaults
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: key)
            }
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
}
