import SwiftUI
import UniformTypeIdentifiers

struct DetailAccountDrag: Codable, Transferable {
    // A scoped MIME type keeps unrelated text, files and external drops off these cards.
    private static let contentType = UTType(mimeType: "application/vnd.minget.account-order+json",
                                            conformingTo: .json)!

    let panelID: UUID
    let accountID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
            .visibility(.ownProcess)
    }
}

private struct DetailAccountDragKey: EnvironmentKey {
    static let defaultValue: DetailAccountDrag? = nil
}

private extension EnvironmentValues {
    var detailAccountDrag: DetailAccountDrag? {
        get { self[DetailAccountDragKey.self] }
        set { self[DetailAccountDragKey.self] = newValue }
    }
}

private struct DetailAccountDragHandle: ViewModifier {
    let name: String
    @Environment(\.detailAccountDrag) private var payload

    func body(content: Content) -> some View {
        if let payload {
            content
                .contentShape(Rectangle())
                .draggable(payload) {
                    HStack(spacing: 8) {
                        content
                        Text(name).font(.headline).lineLimit(1)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .help("拖动图标到另一个账号可调整顺序")
        } else {
            content
        }
    }
}

extension View {
    func detailAccountDragHandle(name: String) -> some View {
        modifier(DetailAccountDragHandle(name: name))
    }
}

/// macOS handles scrolling and cancellation. The entire rendered card is a target, so
/// an expanded quota group, a connection error or a compact balance card needs no pitch.
struct DetailAccountDropTarget: ViewModifier {
    let payload: DetailAccountDrag
    let orderedIDs: [String]
    let move: (String, String) -> Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .environment(\.detailAccountDrag, payload)
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: DetailAccountDrag.self) { items, _ in
                guard items.count == 1, let source = items.first, source.panelID == payload.panelID else { return false }
                return move(source.accountID, payload.accountID)
            } isTargeted: { targeted = $0 }
            .accessibilityAction(named: "账号上移") { step(by: -1) }
            .accessibilityAction(named: "账号下移") { step(by: 1) }
    }

    private func step(by delta: Int) {
        guard let origin = orderedIDs.firstIndex(of: payload.accountID),
              orderedIDs.indices.contains(origin + delta) else { return }
        _ = move(payload.accountID, orderedIDs[origin + delta])
    }
}
