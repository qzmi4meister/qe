import Foundation

/// QE-local preferences. They do not change Launch Services defaults.
public struct FileAssociations {
    private let preferences: UserDefaults
    private let key = "fileAssociations"

    public init(preferences: UserDefaults) { self.preferences = preferences }

    public static func fileExtension(for file: URL) -> String? {
        guard file.isFileURL, !file.pathExtension.isEmpty else { return nil }
        return file.pathExtension.lowercased()
    }

    public func application(for file: URL) -> (url: URL, bundleIdentifier: String?)? {
        guard let ext = Self.fileExtension(for: file),
              let record = records[ext], let path = record["path"], path.hasPrefix("/") else { return nil }
        return (URL(fileURLWithPath: path), record["bundleIdentifier"])
    }

    public func remember(_ application: URL, bundleIdentifier: String?, for file: URL) {
        guard application.isFileURL, let ext = Self.fileExtension(for: file) else { return }
        var updated = records
        var record = ["path": application.path]
        record["bundleIdentifier"] = bundleIdentifier
        updated[ext] = record
        preferences.set(updated, forKey: key)
    }

    public func reset(for file: URL) {
        guard let ext = Self.fileExtension(for: file) else { return }
        var updated = records
        updated.removeValue(forKey: ext)
        preferences.set(updated, forKey: key)
    }

    private var records: [String: [String: String]] {
        preferences.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
    }
}
