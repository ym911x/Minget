import Foundation
import Combine

enum SettingsSection: String, CaseIterable, Identifiable {
    case accounts, menuBar, detail, schedules, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accounts: return "账号"
        case .menuBar: return "菜单栏"
        case .detail: return "详情显示"
        case .schedules: return "刷新与点火"
        case .about: return "关于与诊断"
        }
    }
    var symbol: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .menuBar: return "menubar.rectangle"
        case .detail: return "rectangle.grid.1x2"
        case .schedules: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    private let defaults: UserDefaults
    @Published var firstRun = false
    @Published var section: SettingsSection {
        didSet { defaults.set(section.rawValue, forKey: "settings.section.v1") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        section = SettingsSection(rawValue: defaults.string(forKey: "settings.section.v1") ?? "") ?? .menuBar
    }
}
