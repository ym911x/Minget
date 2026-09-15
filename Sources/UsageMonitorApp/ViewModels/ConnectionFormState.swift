import Foundation
import UsageMonitorCore

/// Collapsible connection-form state for one provider (Round 7 requirement 4/5).
///
/// The rules live here, not in the view, so they are testable without AppKit:
/// - a successful keychain write clears the draft and collapses the form; the user sees
///   the collapsed section with its feedback line instead of an empty input area,
/// - a failed write keeps the draft and the expanded form for retry,
/// - an auth failure keeps the form collapsible and re-expandable, so the key can be
///   replaced,
/// - the verification feedback is NOT part of the form: it renders in the always-visible
///   provider section, so collapsing can never hide it.
@MainActor
final class ConnectionFormState: ObservableObject {

    let platform: ProviderPlatform
    @Published var isExpanded = false
    @Published var draft = ""
    private let model: UsageViewModel

    init(model: UsageViewModel, platform: ProviderPlatform) {
        self.model = model
        self.platform = platform
    }

    var canSave: Bool {
        return !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func toggle() {
        isExpanded.toggle()
    }

    func collapse() {
        isExpanded = false
    }

    /// The 保存 action. Returns true when the keychain accepted the key; only then is the
    /// draft cleared and the form collapsed. Verification continues on the view model and
    /// reports through `credentialFeedback`.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        let saved: Bool
        switch platform {
        case .deepseek: saved = model.saveDeepSeekKey(draft)
        case .commandcode: saved = model.saveCommandCodeKey(draft)
        case .codex: return false
        }
        if saved {
            draft = ""
            isExpanded = false
        }
        return saved
    }

    /// Removes the stored credential, its caches and any suspension; the draft clears so
    /// a replacement can be typed immediately. The form stays where it is.
    func deleteCredential() {
        switch platform {
        case .deepseek: model.deleteDeepSeekKey()
        case .commandcode: model.deleteCommandCodeKey()
        case .codex: return
        }
        draft = ""
    }

}
