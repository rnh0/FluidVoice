import Foundation

extension Notification.Name {
    static let transcriptionHistoryRetentionDidChange = Notification.Name("TranscriptionHistoryRetentionDidChange")
}

extension SettingsStore {
    enum HistoryRetention: Int, CaseIterable, Identifiable {
        case oneDay = 1
        case sevenDays = 7
        case thirtyDays = 30
        case ninetyDays = 90
        case oneYear = 365
        case forever = 0

        static let defaultValue: HistoryRetention = .thirtyDays

        var id: Int {
            self.rawValue
        }

        var displayName: String {
            switch self {
            case .oneDay: "1 day"
            case .sevenDays: "7 days"
            case .thirtyDays: "30 days"
            case .ninetyDays: "90 days"
            case .oneYear: "1 year"
            case .forever: "Forever"
            }
        }

        /// Entries older than this are deleted; nil keeps everything.
        func cutoff(now: Date) -> Date? {
            guard self != .forever else { return nil }
            return now.addingTimeInterval(-Double(self.rawValue) * 86_400)
        }
    }

    private var historyRetentionKey: String { "TranscriptionHistoryRetentionDays" }
    private var saveWindowTitlesInHistoryKey: String { "SaveWindowTitlesInHistory" }

    /// How long dictation history (text and saved audio) is kept. Starred entries are kept.
    var transcriptionHistoryRetention: HistoryRetention {
        get {
            guard let raw = UserDefaults.standard.object(forKey: self.historyRetentionKey) as? Int else {
                return .defaultValue
            }
            return HistoryRetention(rawValue: raw) ?? .defaultValue
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: self.historyRetentionKey)
            NotificationCenter.default.post(name: .transcriptionHistoryRetentionDidChange, object: nil)
        }
    }

    /// Window titles often contain document names, email subjects or URLs. Off by default.
    var saveWindowTitlesInHistory: Bool {
        get { UserDefaults.standard.object(forKey: self.saveWindowTitlesInHistoryKey) as? Bool ?? false }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: self.saveWindowTitlesInHistoryKey)
        }
    }
}
