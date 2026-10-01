import Foundation
import Combine
import UsageMonitorCore

@MainActor
final class AntigravityLoginModel: ObservableObject {
    @Published private(set) var screen = "正在启动官方登录…"
    @Published private(set) var authenticationURL: URL?
    @Published private(set) var status = "请阅读官方提示，并使用下方按钮作出选择。可选数据收集请选择关闭。"
    @Published private(set) var finished = false
    @Published private(set) var successful = false
    @Published private(set) var submitted = false
    @Published private(set) var stage: AntigravityLoginSession.Stage = .starting
    let slot: AntigravitySlot
    private let store: AntigravityProfileStore
    private let uuid: UUID
    private var session: AntigravityLoginSession?
    private var generation = UUID()
    private var completion: (AntigravityConnection) -> Void

    init(slot: AntigravitySlot, store: AntigravityProfileStore = AntigravityProfileStore(),
         completion: @escaping (AntigravityConnection) -> Void) {
        self.slot = slot; self.store = store; self.uuid = UUID(); self.completion = completion
    }
    func start() {
        guard session == nil, !finished else { return }
        do { try store.prepare(uuid) } catch { status = "无法创建本机账号目录"; finished = true; return }
        let session = AntigravityLoginSession(environment: .init(executable: AntigravityCLILocator.executable, home: store.home(uuid)))
        self.session = session
        let current = generation
        let weakModel = WeakAntigravityLoginModel(self)
        let pendingStore = store, pendingUUID = uuid
        DispatchQueue.global(qos: .userInitiated).async {
            session.run { event in
                Task { @MainActor in
                    guard let model = weakModel.value, model.generation == current, !model.finished else { return }
                    model.receive(event)
                }
            }
            Task { @MainActor in
                if let model = weakModel.value {
                    guard model.stage == .cancelled else { return }
                }
                try? pendingStore.removeProfile(pendingUUID)
            }
        }
    }
    func navigate(_ input: AntigravityLoginSession.Navigation) { session?.navigate(input) }
    @discardableResult func submit(_ code: String) -> Bool {
        guard session?.submit(code: code.trimmingCharacters(in: .whitespacesAndNewlines)) == true else {
            status = "授权码未提交：请使用本次官方页面的完整授权码（不要粘贴网址），并检查登录是否已超时"; return false
        }
        submitted = true; stage = .verifying; authenticationURL = nil
        screen = "授权码已提交，正在等待官方身份确认…"
        status = "等待官方确认，最多 45 秒。若出现条款或其他引导，请按提示完成。"
        return true
    }
    func retry() {
        guard finished, !successful, stage == .failed else { return }
        generation = UUID(); session = nil; finished = false; submitted = false
        stage = .starting; authenticationURL = nil; screen = "正在重新确认官方身份…"
        status = "重新启动此账号的官方 CLI；若授权仍有效，会继续确认身份。"
        start()
    }
    func cancel() {
        if finished { if !successful { cleanupPending() }; return }
        generation = UUID(); session?.cancel(); finished = true; stage = .cancelled; authenticationURL = nil
        status = "登录已取消，原有连接保留"
    }
    private func cleanupPending() {
        // Terminal events arrive only after the session has killed and joined its child.
        try? store.removeProfile(uuid)
    }
    private func receive(_ event: AntigravityLoginSession.Event) {
        switch event {
        case .stage(let stage):
            self.stage = stage
            if stage == .onboarding { authenticationURL = nil; status = "请处理下方官方引导，可选数据收集保持关闭。" }
        case .screen(let text, let url): screen = text; authenticationURL = url
        case .failed(let failure):
            finished = true; stage = .failed; authenticationURL = nil
            switch failure {
            case .launch: status = "官方 CLI 缺失或不兼容，请准备已验证版本"
            case .timedOut: status = "登录超时，账号未连接；可重试官方身份确认，关闭窗口会清理本次待连接目录"
            case .confirmationTimedOut: status = "提交后 45 秒内未取得官方身份，账号未连接；请关闭后重新登录"
            case .inputFailed: status = "无法将完整授权码交给官方 CLI，账号未连接；请重新登录"
            case .exited: status = "官方登录进程已退出，账号未提交"
            case .licenseUnavailable: status = "Google 官方套餐读取或选择失败，账号未连接；详见下方提示"
            case .authenticationTransport: status = "官方令牌交换失败（网络或系统证书校验），账号未连接；原有连接保留"
            case .authenticationRejected: status = "官方拒绝了授权码，请关闭后重新登录；原有连接保留"
            case .unsupportedPrompt: status = "官方 CLI 出现未识别的交互提示，已停止；请更新适配后重试"
            case .outputLimit: status = "官方输出超出上限，账号未提交"
            }
            // Keep this pending CLI profile until retry or window close. No connection is committed.
        case .identity(let email):
            authenticationURL = nil
            do {
                let connection = try store.commit(slot: slot, uuid: uuid, email: email)
                finished = true; successful = true
                screen = "官方身份已确认：\(email)"
                status = "已登录，额度读取状态会单独显示"
                completion(connection)
            } catch AntigravityProfileStore.Failure.duplicateIdentity {
                finished = true; status = "该 Google 账号已连接到另一槽位，原连接保留"; cleanupPending()
            } catch {
                finished = true; status = "无法保存确认后的账号，原连接保留"; cleanupPending()
            }
        }
    }
}

private final class WeakAntigravityLoginModel: @unchecked Sendable {
    weak var value: AntigravityLoginModel?
    init(_ value: AntigravityLoginModel) { self.value = value }
}
