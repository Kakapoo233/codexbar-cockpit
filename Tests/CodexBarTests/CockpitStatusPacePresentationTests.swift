import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct CockpitStatusPacePresentationTests {
    private let fixture = CockpitRecommendationPaceIntegrationTests()

    @Test(arguments: [false, true], [0.0, 10.0])
    func `store daily pace reaches native button with signed text and observed direction color`(
        complete: Bool,
        observedUse: Double) throws
    {
        try self.fixture.withFixture { store, plans, settings in
            let snapshot = self.fixture.ingestDay(plans, complete: complete, observedUse: observedUse)
            let pace = try #require(store.cockpitRecommendationPace(
                provider: .codex, snapshot: snapshot, now: self.fixture.now))
            #expect(pace.isLowerBound == !complete)
            #expect(observedUse == 0 ? pace.deltaPercent < 0 : pace.deltaPercent > 0)
            let data = self.fixture.render(store, snapshot: snapshot)
            let presentation = try #require(data.pacePresentations[.weekly])
            #expect(presentation.roundedObservedDelta == pace.deltaPercent.rounded())
            #expect(presentation.isLowerBound == !complete)
            #expect(data.pacePresentations[.automatic] == presentation)
            #expect(data.pacePresentations[.session] == nil)
            #expect(data.metrics.weeklyPaceDelta == (complete ? pace.deltaPercent.rounded() : nil))
            #expect(data.metrics.automaticPaceDelta == (complete ? pace.deltaPercent.rounded() : nil))
            let renderer = MenuBarLayoutRenderer()
            let output = self.render(renderer, data: data)
            #expect(output.attributedTitle.string == CockpitRecommendationPaceText.statusItemText(pace: pace))
            #expect(!output.attributedTitle.string.contains("≥"))
            #expect(!output.attributedTitle.string.contains("≤"))
            #expect(output.accessibilityLabel.contains(presentation.explanation))
            #expect(output.toolTip?.contains(presentation.explanation) == true)
            let color: NSColor = pace.deltaPercent < 0 ? .systemGreen : .systemRed
            #expect(self.color(output) == (complete ? color : color.withAlphaComponent(0.65)))
            let button = NSButton()
            _ = StatusItemController.applyMenuBarLayoutContent(output, for: button, gap: .regular)
            #expect(button.attributedTitle.isEqual(to: output.attributedTitle))
            #expect(button.accessibilityTitle() == output.accessibilityLabel)
            #expect(button.toolTip == output.toolTip)
            settings.menuBarPaceReservePositive = true
            let flipped = self.render(renderer, data: self.fixture.render(store, snapshot: snapshot))
            #expect(flipped.attributedTitle.string ==
                CockpitRecommendationPaceText.statusItemText(pace: pace, reservePositive: true))
            #expect(flipped.attributedTitle.string != output.attributedTitle.string)
            #expect(self.color(flipped) == self.color(output))
            _ = StatusItemController.applyMenuBarLayoutContent(flipped, for: button, gap: .regular)
            #expect(button.attributedTitle.string == flipped.attributedTitle.string)
            #expect(button.toolTip == flipped.toolTip)
        }
    }

    @Test(arguments: [false, true])
    func `partial color dims independently for stale and returns full strength in high contrast`(
        complete: Bool) throws
    {
        try self.fixture.withFixture { store, plans, _ in
            let snapshot = self.fixture.ingestDay(plans, complete: complete)
            let data = self.fixture.render(store, snapshot: snapshot)
            let renderer = MenuBarLayoutRenderer()
            for stale in [false, true] {
                for highContrast in [false, true] {
                    let output = self.render(renderer, data: data, stale: stale, highContrast: highContrast)
                    let alpha = highContrast ? 1.0 : (stale ? 0.5 : (complete ? 1.0 : 0.65))
                    let expected = alpha == 1 ? NSColor.systemRed : NSColor.systemRed.withAlphaComponent(alpha)
                    #expect(self.color(output) == expected)
                    let button = NSButton()
                    _ = StatusItemController.applyMenuBarLayoutContent(output, for: button, gap: .regular)
                    #expect(button.attributedTitle.isEqual(to: output.attributedTitle))
                }
            }
            let disabled = self.render(renderer, data: data, colorPace: false)
            #expect(self.color(disabled) == NSColor.controlTextColor)
            #expect(disabled.toolTip?.isEmpty == false)
        }
    }

    @Test(arguments: [false, true])
    func `rounded zero and missing daily pace stay neutral and missing data clears button help`(
        complete: Bool) throws
    {
        try self.fixture.withFixture { store, plans, _ in
            let snapshot = self.fixture.ingestDay(plans, complete: complete, observedUse: 5.5)
            let data = self.fixture.render(store, snapshot: snapshot)
            #expect(data.pacePresentations[.weekly]?.roundedObservedDelta == 0)
            let renderer = MenuBarLayoutRenderer()
            let zero = self.render(renderer, data: data)
            #expect(zero.attributedTitle.string == "0%")
            #expect(self.color(zero) == NSColor.controlTextColor)
            let button = NSButton()
            _ = StatusItemController.applyMenuBarLayoutContent(zero, for: button, gap: .regular)
            #expect(button.toolTip?.isEmpty == false)
            let missingData = self.fixture.render(store, snapshot: snapshot, local: false)
            #expect(missingData.pacePresentations.isEmpty)
            #expect(missingData.metrics.weeklyPaceDelta == nil)
            let missing = self.render(renderer, data: missingData)
            #expect(missing.attributedTitle.string == "–")
            #expect(self.color(missing) == NSColor.controlTextColor)
            #expect(missing.toolTip == nil)
            _ = StatusItemController.applyMenuBarLayoutContent(missing, for: button, gap: .regular)
            #expect(button.toolTip == nil)
            #expect(button.accessibilityTitle() == missing.accessibilityLabel)
        }
    }

    @Test
    func `coverage changes invalidate cached same integer text and pace help only follows rendered tokens`() throws {
        let renderer = MenuBarLayoutRenderer()
        let button = NSButton()
        var full: MenuBarLayoutRenderedTitle?
        for complete in [true, false] {
            try self.fixture.withFixture { store, plans, _ in
                let snapshot = self.fixture.ingestDay(plans, complete: complete)
                let data = self.fixture.render(store, snapshot: snapshot)
                let output = self.render(renderer, data: data)
                if complete {
                    full = output
                } else {
                    let previous = try #require(full)
                    #expect(previous.attributedTitle.string == output.attributedTitle.string)
                    #expect(previous.toolTip != output.toolTip)
                    #expect(previous.accessibilityLabel != output.accessibilityLabel)
                    #expect(self.color(previous) != self.color(output))
                    #expect(previous.attributedTitle !== output.attributedTitle)
                }
                _ = StatusItemController.applyMenuBarLayoutContent(output, for: button, gap: .regular)
                #expect(button.toolTip == output.toolTip)
                let withoutPace = renderer.render(
                    layout: MenuBarLayout(lines: [[.providerName]]),
                    data: data,
                    icon: nil,
                    options: self.options())
                #expect(withoutPace.toolTip == nil)
                _ = StatusItemController.applyMenuBarLayoutContent(withoutPace, for: button, gap: .regular)
                #expect(button.toolTip == nil)
            }
        }
    }

    @Test
    func `partial precision updates cached help when native integer text stays the same`() throws {
        let renderer = MenuBarLayoutRenderer()
        let button = NSButton()
        var firstData: MenuBarLayoutRenderData?
        var firstOutput: MenuBarLayoutRenderedTitle?
        for observedUse in [10.01, 10.31] {
            try self.fixture.withFixture { store, plans, _ in
                let snapshot = self.fixture.ingestDay(plans, complete: false, observedUse: observedUse)
                let data = self.fixture.render(store, snapshot: snapshot)
                #expect(data.metrics.weeklyPaceDelta == nil)
                #expect(data.metrics.automaticPaceDelta == nil)
                let output = renderer.render(
                    layout: MenuBarLayout(lines: [[.pace(window: .automatic)]]),
                    data: data,
                    icon: nil,
                    options: self.options())
                if let previous = firstOutput, let previousData = firstData {
                    #expect(previous.attributedTitle.string == output.attributedTitle.string)
                    #expect(previousData.pacePresentations[.automatic]?.roundedObservedDelta ==
                        data.pacePresentations[.automatic]?.roundedObservedDelta)
                    #expect(previousData != data)
                    #expect(previous.toolTip != output.toolTip)
                    #expect(previous.accessibilityLabel != output.accessibilityLabel)
                    #expect(previous.attributedTitle !== output.attributedTitle)
                } else {
                    firstData = data
                    firstOutput = output
                }
                _ = StatusItemController.applyMenuBarLayoutContent(output, for: button, gap: .regular)
                #expect(button.toolTip == output.toolTip)
                #expect(button.accessibilityTitle() == output.accessibilityLabel)
                let repeated = renderer.render(
                    layout: MenuBarLayout(lines: [[.pace(window: .automatic)]]),
                    data: data,
                    icon: nil,
                    options: self.options())
                #expect(repeated.attributedTitle === output.attributedTitle)
            }
        }
    }

    @Test(arguments: [MenuBarIconStyle.bars, .iconAndPercent])
    func `legacy controller render and cached skip clear prior daily pace accessibility`(
        style: MenuBarIconStyle) throws
    {
        try self.fixture.withFixture { store, plans, settings in
            settings.mergeIcons = true
            settings.unifiedIconSource = .currentSelection
            settings.selectedMenuProvider = .codex
            settings.mergedMenuLastSelectedWasOverview = false
            settings.menuBarIconStyle = style
            enableTestProviders([.codex, .claude], settings: settings)
            #expect(!settings.hasStoredMenuBarLayout)
            #expect(settings.menuBarLayoutResolution(for: .codex).usesLegacyRendering)
            let snapshot = self.fixture.ingestDay(plans, complete: false)
            store._setSnapshotForTesting(snapshot, provider: .codex)
            for provider in [UsageProvider.codex, .claude] {
                store.accountInfoCache[provider.instanceID] = .init(
                    account: AccountInfo(email: nil, plan: nil),
                    configRevision: settings.configRevision,
                    expiresAt: .distantFuture)
            }
            let controller = StatusItemController(
                store: store,
                settings: settings,
                account: AccountInfo(email: nil, plan: nil),
                updater: DisabledUpdaterController(),
                preferencesSelection: PreferencesSelection(),
                statusBar: testStatusBar(),
                menuCardRenderingEnabled: false,
                menuRefreshEnabled: false,
                observeProviderConfigNotifications: false)
            defer { controller.releaseStatusItemsForTesting() }
            controller.statusItem.isVisible = false
            #expect(controller.shouldMergeIcons)
            #expect(controller.primaryProviderForUnifiedIcon() == UsageProvider.codex.instanceID)
            let button = try #require(controller.statusItem.button)
            let data = self.fixture.render(store, snapshot: snapshot)
            let previous = self.render(MenuBarLayoutRenderer(), data: data)
            let explanation = try #require(data.pacePresentations[.weekly]?.explanation)
            let oldHelp = try #require(previous.toolTip)
            controller.lastAppliedMergedIconRenderSignature = nil
            for expectCached in [false, true] {
                _ = StatusItemController.applyMenuBarLayoutContent(previous, for: button, gap: .regular)
                #expect(button.toolTip == oldHelp)
                #expect(button.accessibilityHelp() == oldHelp)
                #expect(button.accessibilityTitle()?.contains(explanation) == true)
                #expect(controller.applyIcon(phase: nil) == expectCached)
                #expect(button.toolTip == nil)
                #expect(button.accessibilityHelp()?.contains(explanation) != true)
                #expect(button.accessibilityTitle() == StatusItemController.statusItemAccessibilityTitle(
                    isDebugApp: StatusItemController.isDebugApp(bundleIdentifier: Bundle.main.bundleIdentifier)))
                #expect(button.accessibilityTitle()?.contains(explanation) != true)
            }
        }
    }

    private func render(
        _ renderer: MenuBarLayoutRenderer,
        data: MenuBarLayoutRenderData,
        stale: Bool = false,
        highContrast: Bool = false,
        colorPace: Bool = true) -> MenuBarLayoutRenderedTitle
    {
        renderer.render(
            layout: MenuBarLayout(lines: [[.pace(window: .weekly)]]),
            data: data,
            icon: nil,
            options: self.options(stale: stale, highContrast: highContrast, colorPace: colorPace))
    }

    private func options(
        stale: Bool = false,
        highContrast: Bool = false,
        colorPace: Bool = true) -> MenuBarLayoutRenderOptions
    {
        MenuBarLayoutRenderOptions(
            size: .regular,
            highContrast: highContrast,
            showUsed: true,
            conditionals: [],
            appearanceName: NSAppearance.Name.aqua.rawValue,
            isDebugApp: false,
            isStale: stale,
            now: self.fixture.now,
            colorPace: colorPace)
    }

    private func color(_ output: MenuBarLayoutRenderedTitle) -> NSColor? {
        guard output.attributedTitle.length > 0 else { return nil }
        return output.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    }
}
