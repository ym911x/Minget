import SwiftUI
import AppKit
import UsageMonitorCore

struct AntigravityLoginView: View {
    @ObservedObject var model: AntigravityLoginModel
    let close: () -> Void
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录 Google 账号").font(.title2.bold())
            Text(model.status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            ScrollView([.horizontal, .vertical]) {
                Text(model.screen).font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
            }.background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            if model.stage == .onboarding && !model.finished {
                HStack {
                    Button("↑ 上一项") { model.navigate(.up) }
                    Button("↓ 下一项") { model.navigate(.down) }
                    Button("← 左一项") { model.navigate(.left) }
                    Button("→ 右一项") { model.navigate(.right) }
                    Button("切换勾选") { model.navigate(.toggle) }.disabled(!model.screen.contains("服务条款与可选数据收集"))
                    Button("确认当前选择") { model.navigate(.confirm) }
                }
                Text("上方是官方 CLI 的实时提示。条款、数据选择和目录信任需由你确认。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let url = model.authenticationURL, !model.finished, model.stage == .awaitingCode {
                Button("打开官方认证页面") { NSWorkspace.shared.open(url) }
                HStack {
                    SecureField("粘贴页面给出的一次性授权码", text: $code).textFieldStyle(.roundedBorder)
                    Button("提交授权码") { if model.submit(code) { code = "" } }.disabled(code.isEmpty || model.stage != .awaitingCode)
                }
                Text("在浏览器选择此槽位的 Google 账号，完成后复制授权码到这里。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                if model.finished && !model.successful && model.stage == .failed {
                    Button("重试官方身份确认") { code = ""; model.retry() }
                }
                Spacer()
                Button(model.finished ? (model.successful ? "完成（已登录）" : "关闭（未登录）") : "取消登录") { code = ""; model.cancel(); close() }
            }
        }.padding(18).frame(width: 760, height: 620).onAppear { model.start() }
    }
}

@MainActor
final class AntigravityLoginWindowController: NSWindowController, NSWindowDelegate {
    let login: AntigravityLoginModel
    private let onClose: () -> Void
    init(slot: AntigravitySlot, store: AntigravityProfileStore = AntigravityProfileStore(),
         completion: @escaping (AntigravityConnection) -> Void, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        login = AntigravityLoginModel(slot: slot, store: store, completion: completion)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Minget · Google 官方登录"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: AntigravityLoginView(model: login) { [weak self] in self?.close() })
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func windowWillClose(_ notification: Notification) { login.cancel(); onClose() }
}
