import Foundation

struct AnalyticsConfig {
    let postHogApiKey: String
    let postHogHost: String

    /// Default EU ingestion host.
    nonisolated static let defaultEUHost = "https://eu.i.posthog.com"

    nonisolated static func fromBundle() -> AnalyticsConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        #if FLUID_NO_ANALYTICS
        let key = ""
        #else
        let key = (info["POSTHOG_API_KEY"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        #endif
        let host = (info["POSTHOG_HOST"] as? String ?? AnalyticsConfig.defaultEUHost).trimmingCharacters(in: .whitespacesAndNewlines)
        return AnalyticsConfig(postHogApiKey: key, postHogHost: host.isEmpty ? AnalyticsConfig.defaultEUHost : host)
    }

    nonisolated var isConfigured: Bool {
        !self.postHogApiKey.isEmpty
    }
}
