import Combine
import Foundation

/// Fork feature: the secondary dictation shortcut can dictate with its own speech model (for example
/// Whisper pinned to Swedish), and the primary shortcut switches back. See PRIVACY.md.
extension SettingsStore {
    private var secondaryDictationSpeechModelKey: String { "SecondaryDictationSpeechModel" }
    private var primarySpeechModelRestoreKey: String { "PrimarySpeechModelRestore" }

    /// The model the secondary dictation shortcut switches to; nil keeps the current model.
    var secondaryDictationSpeechModel: SpeechModel? {
        get {
            UserDefaults.standard.string(forKey: self.secondaryDictationSpeechModelKey).flatMap(SpeechModel.init(rawValue:))
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue?.rawValue, forKey: self.secondaryDictationSpeechModelKey)
            if newValue == nil {
                self.primarySpeechModelRestore = nil
            }
        }
    }

    /// The model that was active before the secondary shortcut switched away from it.
    var primarySpeechModelRestore: SpeechModel? {
        get {
            UserDefaults.standard.string(forKey: self.primarySpeechModelRestoreKey).flatMap(SpeechModel.init(rawValue:))
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: self.primarySpeechModelRestoreKey)
        }
    }

    struct ShortcutSpeechModelSwitch: Equatable {
        /// The model to activate, or nil to keep the current one.
        let activate: SpeechModel?
        /// The new value for `primarySpeechModelRestore`.
        let restore: SpeechModel?
    }

    /// Decides which model a dictation shortcut should use. Pure, so it can be tested without the app.
    static func shortcutSpeechModelSwitch(
        for slot: DictationShortcutSlot,
        current: SpeechModel,
        secondary: SpeechModel?,
        restore: SpeechModel?
    ) -> ShortcutSpeechModelSwitch {
        switch slot {
        case .secondary:
            guard let secondary, secondary != current else {
                return ShortcutSpeechModelSwitch(activate: nil, restore: restore)
            }
            return ShortcutSpeechModelSwitch(activate: secondary, restore: current)
        case .primary:
            // Only undo a switch the secondary shortcut made; a model chosen in Settings stays.
            guard let restore, let secondary, current == secondary, restore != current else {
                return ShortcutSpeechModelSwitch(activate: nil, restore: nil)
            }
            return ShortcutSpeechModelSwitch(activate: restore, restore: nil)
        }
    }
}
