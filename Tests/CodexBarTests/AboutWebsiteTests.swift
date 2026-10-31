import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct AboutWebsiteTests {
    @Test
    func `about links lead to the fork project and its support resources`() throws {
        let source = try Self.aboutSource()
        #expect(try Self.websiteURL() == "https://github.com/Kakapoo233/codexbar-cockpit")
        #expect(source.contains("https://github.com/Kakapoo233/codexbar-cockpit/issues"))
        #expect(source.contains("https://github.com/Kakapoo233/codexbar-cockpit/blob/main/docs/cockpit/CHANGELOG.md"))
        #expect(source.contains("https://github.com/steipete/CodexBar"))
        #expect(source.contains("https://github.com/HouSiyuan2001/codex-cockpit"))
        #expect(!source.contains("mailto:peter@steipete.me"))
        #expect(!source.contains("https://twitter.com/steipete"))
    }

    @Test
    func `about links render without opening a browser`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_ABOUT_WEBSITE_PROOF_DIR"] else { return }
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let url = try Self.websiteURL()
            let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 16) {
                AboutLinkRow(icon: "globe", title: L("link_github"), url: url)
                Divider()
                Text("Configured destination (proof annotation)").font(.caption)
                Text(url).font(.system(.body, design: .monospaced))
            }
            .padding(24)
            .frame(width: 530)
            .environment(\.colorScheme, .light)
            .background(Color.white))
            renderer.scale = 2
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("about.png"))
        }
    }

    private static func aboutSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBar/Settings/PreferencesAboutPane.swift"),
            encoding: .utf8)
    }

    private static func websiteURL() throws -> String {
        let source = try Self.aboutSource()
        let pattern = #"title:\s*L\("link_github"\),\s*url:\s*"([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try #require(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let range = try #require(Range(match.range(at: 1), in: source))
        return String(source[range])
    }
}
