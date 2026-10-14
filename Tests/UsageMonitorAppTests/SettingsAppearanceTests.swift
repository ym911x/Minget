import AppKit
import SwiftUI
import XCTest
@testable import UsageMonitorApp

/// The settings window's own presentation rules: one explanation per pane, one resolvable
/// symbol and colour per sidebar tile, and no invented version number when the host has no
/// app metadata. Behaviour of the controls themselves is covered by the wiring tests.
@MainActor
final class SettingsAppearanceTests: XCTestCase {

    func testEveryPaneExplainsItselfExactlyOnce() {
        let subtitles = SettingsSection.allCases.map(\.subtitle)
        XCTAssertEqual(subtitles.count, 5)
        XCTAssertEqual(Set(subtitles).count, subtitles.count, "每个分组的说明应当互不相同")
        XCTAssertTrue(subtitles.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertTrue(SettingsSection.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testEveryPaneSymbolResolvesAndEveryTintIsDistinct() {
        for section in SettingsSection.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil),
                            "\(section.rawValue) 的 SF Symbol 必须能在本机解析")
        }
        XCTAssertEqual(Set(SettingsSection.allCases.map(\.tint)).count, SettingsSection.allCases.count,
                       "五个分组的侧栏颜色应当互不相同")
    }

    func testSidebarMarkGeometryKeepsTheGlyphInsideItsTile() {
        XCTAssertLessThan(SettingsStyle.markCorner, SettingsStyle.markSize / 2, "圆角不得超过方块的一半")
        XCTAssertLessThan(SettingsStyle.markGlyphSize, SettingsStyle.markSize, "字形必须小于方块")
        XCTAssertGreaterThan(SettingsStyle.noteSize, 0)
        XCTAssertGreaterThan(SettingsStyle.pageTitleSize, SettingsStyle.noteSize)
        XCTAssertGreaterThan(SettingsStyle.pagePadding, 0)
    }

    /// A test host or preview has no Minget Info.plist. Both surfaces must then report an
    /// unknown version instead of the stale literal they used to fall back to.
    func testVersionIsUnknownWithoutAppBundleMetadata() {
        let host = Bundle(for: SettingsAppearanceTests.self)
        XCTAssertNotEqual(host.object(forInfoDictionaryKey: "CFBundleName") as? String, "Minget")
        XCTAssertEqual(MingetSettingsView.appVersion(bundle: host), "—")
        XCTAssertNil(UsagePanelView.appVersion(bundle: host))
    }
}
