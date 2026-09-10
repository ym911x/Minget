import AppKit
import SwiftUI

struct MingetAboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 104, height: 104)
                .accessibilityLabel("M²")

            Text("明明有数 · Minget")
                .font(.system(size: 20, weight: .bold))

            VStack(spacing: 3) {
                Text("你的 AI 使用，心里有数。")
                    .font(.system(size: 13, weight: .medium))
                Text("Your AI usage, at a glance.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("版本 \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("统一查看和管理个人 AI 服务使用状态、可用资源与成本信息。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
        }
        .padding(28)
        .frame(width: 320, height: 300)
    }
}
