import Foundation
import Security

/// The single place in the process that touches the keychain.
///
/// Problems this exists to remove (KEYCHAIN_REVISION_PLAN.md P1.2, P1.3, P1.6):
/// - credential reads used to happen inline from `init`, `report` and every status query, so
///   a keychain decision could block application construction and repeat on every redraw,
/// - one business read could fetch the same key twice,
/// - every failure collapsed into `nil`, so the UI could not tell "not saved yet" from
///   "you refused access" and reported the wrong one,
/// - a refused access was retried immediately by the next status query, which is the shape
///   of a prompt loop.
///
/// Design:
/// - one serial queue performs every keychain call, so the process-wide interaction policy
///   can never overlap between a background read and a user-initiated one,
/// - concurrent requests for the same credential coalesce onto one task,
/// - the outcome of the last access is remembered per credential, so `needsAuthorization`
///   becomes a state the UI can show instead of a secret that keeps being re-requested,
/// - successful values live in memory only, for the lifetime of the process; the keychain
///   remains the only persistence.
public final class CredentialAccessCoordinator: @unchecked Sendable {

    private struct InFlight {
        let id: Int
        let purpose: CredentialAccessPurpose
        let task: Task<CredentialAccessOutcome, Never>
    }

    private let store: ProviderCredentialStoring
    /// Serial executor for every keychain call in this process.
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var phases: [ProviderCredentialKey: ProviderCredentialPhase] = [:]
    private var lastOutcomes: [ProviderCredentialKey: CredentialAccessOutcome] = [:]
    /// In-memory only. Cleared on disconnect, on a failed read, and when the process exits.
    private var secrets: [ProviderCredentialKey: String] = [:]
    private var inFlight: [ProviderCredentialKey: InFlight] = [:]
    private var nextTaskID = 0

    /// Called after any change to a credential's phase. Delivered on an arbitrary queue; the
    /// owner hops to the main actor before touching UI state.
    public var onPhaseChange: (() -> Void)?

    public init(store: ProviderCredentialStoring,
                queue: DispatchQueue = DispatchQueue(label: "local.usagemonitor.credential-access")) {
        self.store = store
        self.queue = queue
    }

    // MARK: - Memory state (callable from any thread, never touches the keychain)

    public func phase(for key: ProviderCredentialKey) -> ProviderCredentialPhase {
        lock.lock(); defer { lock.unlock() }
        return phases[key] ?? .unknown
    }

    /// The last raw outcome, for diagnostics and for the panel's explanation text.
    public func lastOutcome(for key: ProviderCredentialKey) -> CredentialAccessOutcome? {
        lock.lock(); defer { lock.unlock() }
        return lastOutcomes[key]
    }

    /// The value read earlier in this process, if any. Never triggers a keychain call.
    public func cachedSecret(for key: ProviderCredentialKey) -> String? {
        lock.lock(); defer { lock.unlock() }
        return secrets[key]
    }

    /// True once every credential has been read at least once in this process.
    public func hasPrimed(_ keys: [ProviderCredentialKey]) -> Bool {
        keys.allSatisfy { phase(for: $0) != .unknown }
    }

    // MARK: - Reading

    /// Reads one credential.
    ///
    /// The retry policy follows the purpose, not the interaction mode: a purpose the user
    /// originated may make a fresh attempt on a blocked credential, while an automatic purpose
    /// is answered from the remembered outcome so a refusal can never be re-asked by a timer
    /// or a redraw (KEYCHAIN_REVISION_PLAN.md P1.4 and P1.6).
    ///
    /// `interaction` records whether the security framework may show UI and is written to the
    /// diagnostics log. The default read path passes `.allowed`: real-launch verification
    /// showed that a disabled interaction switch refuses even an already-authorised read
    /// (`evidence/logs/13-keychain-background-denial.txt`), which would have forced the user
    /// to press 授权读取 on every launch.
    public func value(for key: ProviderCredentialKey,
                      purpose: CredentialAccessPurpose,
                      interaction: CredentialInteraction) async -> CredentialAccessOutcome {
        // Coalesce onto an in-flight read of the same credential that answers the same kind of
        // question: an automatic request may join any read, a user-initiated one only joins
        // another user-initiated read, so a press is never answered by a refusal recorded for
        // a timer.
        if let existing = inFlightEntry(for: key), canJoin(existing, requested: purpose) {
            let outcome = await existing.task.value
            CredentialAccessLog.record(key: key, purpose: purpose, interaction: interaction,
                                       outcome: outcome, elapsed: 0)
            return outcome
        }

        // A value already read in this process is reused instead of asking again.
        if let secret = cachedSecret(for: key) { return .available(secret) }
        // A refused or failed read is a remembered state, unless this purpose is allowed to
        // make a fresh attempt.
        if !purpose.mayRetryBlocked, let remembered = rememberedOutcome(for: key) { return remembered }
        return await run(key: key, purpose: purpose, interaction: interaction)
    }

    /// First read after launch for the given credentials. Each credential is read at most
    /// once because a known phase is not probed again.
    ///
    /// These reads run with interaction **allowed**, which is a deliberate deviation from
    /// KEYCHAIN_REVISION_PLAN.md P1.4 and is evidence-driven: with the interaction switch
    /// disabled, a read of an already-authorised item was still refused by the framework
    /// (`deniedOrCancelled`, `evidence/logs/13-keychain-background-denial.txt`), so the panel
    /// would have shown 「需要授权」 on every launch and the user would have had to press the
    /// button each time. The stable certificate identity is what stops a prompt loop: one
    /// authorisation per item is remembered by the ACL, and a refusal is remembered by this
    /// coordinator, so neither path can repeat per redraw or per poll.
    public func prime(_ keys: [ProviderCredentialKey]) async {
        for key in keys where phase(for: key) == .unknown {
            _ = await value(for: key, purpose: .startupPrime, interaction: .allowed)
        }
    }

    /// Forces one read even when the phase is already known. Used when a credential changed
    /// outside this process, which only an explicit user action may assume.
    public func refresh(_ key: ProviderCredentialKey,
                        purpose: CredentialAccessPurpose,
                        interaction: CredentialInteraction) async -> CredentialAccessOutcome {
        forget(key)
        return await value(for: key, purpose: purpose, interaction: interaction)
    }

    // MARK: - Writing

    /// Saves a credential and marks it available in memory.
    ///
    /// Synchronous by design: the writer is a form the user just submitted and the form needs
    /// the verdict before it can clear its input. The keychain call itself still runs on the
    /// serial queue, so it cannot overlap a read.
    public func store(_ secret: String, for key: ProviderCredentialKey,
                      purpose: CredentialAccessPurpose = .save) throws {
        let start = DispatchTime.now()
        try queue.sync { try store.save(secret, for: key) }
        let elapsed = Self.seconds(since: start)
        remember(outcome: .available(secret), for: key)
        CredentialAccessLog.record(key: key, purpose: purpose, interaction: .allowed,
                                   outcome: .available(secret), elapsed: elapsed)
        onPhaseChange?()
    }

    /// Removes a credential. A failure is propagated: the caller must not claim the account
    /// was disconnected while the item is still there (KEYCHAIN_REVISION_PLAN.md P1.8).
    public func remove(_ key: ProviderCredentialKey,
                       purpose: CredentialAccessPurpose = .delete) throws {
        let start = DispatchTime.now()
        try queue.sync { try store.delete(key) }
        let elapsed = Self.seconds(since: start)
        remember(outcome: .missing, for: key)
        CredentialAccessLog.record(key: key, purpose: purpose, interaction: .allowed,
                                   outcome: .missing, elapsed: elapsed)
        onPhaseChange?()
    }

    /// Drops everything remembered about a credential without touching the keychain. Used
    /// when an account's numbers are invalidated, not when the credential is removed.
    public func forget(_ key: ProviderCredentialKey) {
        lock.lock()
        phases[key] = .unknown
        lastOutcomes[key] = nil
        secrets[key] = nil
        lock.unlock()
    }

    // MARK: - Internals

    private func run(key: ProviderCredentialKey,
                     purpose: CredentialAccessPurpose,
                     interaction: CredentialInteraction) async -> CredentialAccessOutcome {
        // Registering the task under the lock is what makes concurrent callers share it. The
        // task body only takes the lock again after a real asynchronous hop, so this cannot
        // deadlock; the worst case is that the task waits until this scope exits.
        let handle: InFlight = lock.withLock {
            if let existing = inFlight[key], canJoin(existing, requested: purpose) {
                return existing
            }
            nextTaskID += 1
            let created = InFlight(id: nextTaskID,
                                   purpose: purpose,
                                   task: Task<CredentialAccessOutcome, Never> { [weak self] in
                                       guard let self else { return .unavailable(errSecNotAvailable) }
                                       return await self.perform(key: key, purpose: purpose,
                                                                 interaction: interaction)
                                   })
            inFlight[key] = created
            return created
        }
        let outcome = await handle.task.value
        lock.withLock {
            if inFlight[key]?.id == handle.id { inFlight[key] = nil }
        }
        return outcome
    }

    /// An automatic request may join any in-flight read. A user-initiated request joins only
    /// another user-initiated read, because an automatic read may legitimately have been
    /// refused without asking.
    private func canJoin(_ existing: InFlight, requested: CredentialAccessPurpose) -> Bool {
        if !requested.mayRetryBlocked { return true }
        return existing.purpose.mayRetryBlocked
    }

    private func perform(key: ProviderCredentialKey,
                         purpose: CredentialAccessPurpose,
                         interaction: CredentialInteraction) async -> CredentialAccessOutcome {
        let start = DispatchTime.now()
        // `withCheckedContinuation` keeps the calling task's thread free: the keychain call
        // runs on the serial queue, the caller resumes when it answers.
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<CredentialAccessOutcome, Never>) in
            queue.async {
                continuation.resume(returning: self.store.load(key, interaction: interaction))
            }
        }
        let elapsed = Self.seconds(since: start)
        remember(outcome: outcome, for: key)
        CredentialAccessLog.record(key: key, purpose: purpose, interaction: interaction,
                                   outcome: outcome, elapsed: elapsed)
        onPhaseChange?()
        return outcome
    }

    private func remember(outcome: CredentialAccessOutcome, for key: ProviderCredentialKey) {
        lock.lock()
        phases[key] = Self.phase(for: outcome)
        lastOutcomes[key] = outcome
        secrets[key] = outcome.secret
        lock.unlock()
    }

    /// A blocked or failed credential keeps its last outcome, so the next status query reports
    /// the same thing instead of asking the keychain again.
    private func rememberedOutcome(for key: ProviderCredentialKey) -> CredentialAccessOutcome? {
        lock.lock(); defer { lock.unlock() }
        return lastOutcomes[key]
    }

    private func inFlightEntry(for key: ProviderCredentialKey) -> InFlight? {
        lock.lock(); defer { lock.unlock() }
        return inFlight[key]
    }

    static func phase(for outcome: CredentialAccessOutcome) -> ProviderCredentialPhase {
        switch outcome {
        case .available: return .available
        case .missing: return .missing
        case .interactionRequired, .deniedOrCancelled: return .needsAuthorization
        case .unavailable: return .unavailable
        }
    }

    private static func seconds(since start: DispatchTime) -> TimeInterval {
        let nanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        return TimeInterval(nanos) / 1_000_000_000
    }
}
