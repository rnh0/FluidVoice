import Foundation

// MARK: - Local diagnostics trigger

extension GlobalHotkeyManager {
    /// Fork policy: Debug builds only. Any process can post distributed notifications, so in Release
    /// they must never start recording or paste a transcript, whatever the defaults flag says.
    nonisolated static var debugRemoteTriggersEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "FluidDebugRemoteToggleEnabled")
        #else
        false
        #endif
    }

    /// Lets a local script run the exact hotkey toggle path for latency
    /// reproduction. Inert unless the defaults flag is set on this machine.
    func registerDebugToggleTriggerIfEnabled() {
        guard Self.debugRemoteTriggersEnabled else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.FluidApp.debug.toggleRecording"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                DebugLogger.shared.info("Debug toggle trigger received", source: "GlobalHotkeyManager")
                self?.toggleRecording()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.FluidApp.debug.pasteLastTranscript"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                DebugLogger.shared.info("Debug paste-last trigger received", source: "GlobalHotkeyManager")
                self?.triggerPasteLastTranscription(isAutorepeat: false)
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.FluidApp.debug.showPasteFailure"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                DeliveryFailureOverlayController.shared.show(
                    kind: .noEditableTarget,
                    transcript: "The quick brown fox jumps over the lazy dog and keeps going for a while"
                )
            }
        }
        DebugLogger.shared.info("Debug toggle trigger enabled", source: "GlobalHotkeyManager")
    }
}
