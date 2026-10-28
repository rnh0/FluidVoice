import Combine
import Foundation

/// Applies `SettingsStore.transcriptionHistoryRetention` to dictation history: after loading, after every
/// change (new dictation, backup restore), when the setting changes, and hourly as time passes.
/// Deleting an entry also deletes its saved audio; the search index drops it on its next reconcile.
@MainActor
final class TranscriptionHistoryRetentionService {
    static let shared = TranscriptionHistoryRetentionService()

    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?

    private init() {}

    func start(
        store: TranscriptionHistoryStore = .shared,
        settings: SettingsStore = .shared
    ) {
        guard self.cancellables.isEmpty else { return }

        // @Published emits before the new value is stored, so never mutate history from inside the emission.
        store.loadedEntriesPublisher
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.prune(store: store, settings: settings) }
            .store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: .transcriptionHistoryRetentionDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.prune(store: store, settings: settings) }
            .store(in: &self.cancellables)

        self.timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune(store: store, settings: settings) }
        }
    }

    private func prune(store: TranscriptionHistoryStore, settings: SettingsStore) {
        guard let cutoff = settings.transcriptionHistoryRetention.cutoff(now: Date()) else { return }
        let deleted = store.deleteUnstarredEntries(olderThan: cutoff)
        if deleted > 0 {
            DebugLogger.shared.info("History retention deleted \(deleted) entries", source: "HistoryRetention")
        }
    }
}
