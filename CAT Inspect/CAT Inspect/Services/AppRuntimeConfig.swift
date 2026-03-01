import Foundation

enum AppRuntimeConfig {
    static func string(_ key: String, default defaultValue: String = "") -> String {
        let runtime = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !runtime.isEmpty { return runtime }

        let plist = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !plist.isEmpty { return plist }

        return defaultValue
    }

    static func url(_ key: String, default defaultValue: String) -> URL {
        let raw = string(key, default: defaultValue)
        guard let url = URL(string: raw) else {
            preconditionFailure("Invalid URL for config key: \(key)")
        }
        return url
    }
}

