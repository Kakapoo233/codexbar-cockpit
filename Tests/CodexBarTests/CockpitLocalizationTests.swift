import AppKit
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitLocalizationTests {
    @Test
    func `every existing language contains translated cockpit prose`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent("Sources/CodexBar/Resources")
        let english = try #require(NSDictionary(contentsOf: resources
                .appendingPathComponent("en.lproj/Localizable.strings")) as? [String: String])
        let keys = english.keys.filter { $0.hasPrefix("cockpit_") }
        #expect(keys.count >= 154)
        let prose = [
            "cockpit_ui_preview_note", "cockpit_ui_cost_note", "cockpit_ui_date_note",
            "cockpit_ui_plan_read_error", "cockpit_ui_plan_save_error", "cockpit_ui_import_missing",
        ]
        for language in AppLanguage.allCases where language != .system {
            let catalog = try #require(NSDictionary(contentsOf: resources
                    .appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
            for key in keys {
                let value = try #require(catalog[key], "Missing \(language.rawValue): \(key)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if language != .english {
                for key in prose {
                    #expect(catalog[key] != english[key], "Untranslated \(language.rawValue): \(key)")
                }
            }
        }
    }

    @Test
    func `retained errors resolve their text after a language change`() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("plan.json")
        let corrupt = Data("synthetic corrupt plan".utf8)
        try corrupt.write(to: url)
        let store = CockpitPlanStore(fileURL: url)
        let notice = CockpitLocalizedMessage("cockpit_ui_plan_save_error", "synthetic detail")
        let retry = Date(timeIntervalSince1970: 1_800_000_000)
        let retryNotice = CockpitLocalizedMessage("cockpit_reset_rate_limited", date: retry)
        let english = CodexBarLocalizationOverride.$appLanguage.withValue("en") { store.errorMessage }
        for language in ["zh-Hant", "de", "ar", "fa", "ja"] {
            CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                #expect(store.errorMessage != english)
                #expect(notice.text == L("cockpit_ui_plan_save_error", "synthetic detail"))
                #expect(notice.text.contains("synthetic detail"))
                #expect(retryNotice.text == L("cockpit_reset_rate_limited", CockpitLocalizedMessage.dateText(retry)))
            }
        }
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test(arguments: ["de", "ar", "fa", "ja", "zh-Hant"])
    func `receipt dates and planning percentages follow the selected language`(language: String) {
        CodexBarLocalizationOverride.$appLanguage.withValue(language) {
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let locale = Locale(identifier: language == "ar" ? "ar@numbers=arab" : language)
            #expect(cockpitLocalizedPercent(12.5) == 0.125.formatted(
                .percent.precision(.fractionLength(1)).locale(locale)))
            #expect(CockpitReceiptCardView.dateText(date) == date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(codexBarLocalizedLocale())))
        }
    }

    @Test(arguments: ["de", "ar", "fa", "ja", "zh-Hant"])
    func `localized partial receipts render without account or clipboard access`(language: String) throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
            let receipt = CockpitReceiptModel(
                items: [CockpitReceiptLine(
                    id: "synthetic",
                    title: "Synthetic task · layout preview",
                    providerName: "Codex",
                    currencyCode: "USD",
                    tokens: 123_456,
                    estimatedCost: 1.25,
                    tokensArePartial: true,
                    costIsPartial: true,
                    sessionCount: 3,
                    lineageIsPartial: true)],
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                scopeLabel: CockpitReceiptModel.scopeLabel(for: .rolling(days: 7), timeZone: .gmt))
            let png = try #require(ShareStatsRenderer.pngData(for: receipt))
            let bitmap = try #require(NSBitmapImageRep(data: png))
            #expect(bitmap.pixelsWide == 620)
            #expect(bitmap.pixelsHigh == Int(CockpitReceiptCardView.size(for: receipt).height))
            if let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: directory.appendingPathComponent("cockpit-receipt-synthetic-\(language).png"))
            }
        }
    }
}
