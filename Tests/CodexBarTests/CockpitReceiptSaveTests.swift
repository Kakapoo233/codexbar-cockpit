import AppKit
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitReceiptSaveTests {
    init() {
        _ = NSApplication.shared
    }

    @Test
    func `save returns while the owning preview sheet awaits a destination and rejects duplicate saves`() {
        let owner = NSWindow()
        let panel = RecordingSavePanel()
        var writes = 0
        var outcomes: [CockpitReceiptImageSave.Outcome] = []
        let save = CockpitReceiptImageSave(
            render: { _ in Data([1, 2, 3]) },
            makePanel: { panel },
            write: { _, _ in writes += 1 })
        save.attach(to: owner)

        save.save(self.receipt) { outcomes.append($0) }
        save.save(self.receipt) { outcomes.append($0) }

        #expect(panel.owner === owner)
        #expect(panel.beginCount == 1)
        #expect(save.isSaving)
        #expect(!save.canSave)
        #expect(writes == 0)
        #expect(outcomes.isEmpty)
        panel.complete(nil)
        #expect(outcomes == [.cancelled])
        #expect(!save.isSaving)
        #expect(save.canSave)
        #expect(writes == 0)
    }

    @Test
    func `confirmed destination receives a decodable PNG from the synthetic receipt`() throws {
        let owner = NSWindow()
        let panel = RecordingSavePanel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("receipt.png")
        var outcome: CockpitReceiptImageSave.Outcome?
        let save = CockpitReceiptImageSave(makePanel: { panel })
        save.attach(to: owner)

        save.save(self.receipt) { outcome = $0 }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        panel.complete(destination)

        #expect(outcome == .saved)
        #expect(!save.isSaving)
        let data = try Data(contentsOf: destination)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(NSBitmapImageRep(data: data) != nil)
    }

    @Test
    func `a failed write reports the export error and permits retry`() {
        let owner = NSWindow()
        let panel = RecordingSavePanel()
        var outcome: CockpitReceiptImageSave.Outcome?
        let save = CockpitReceiptImageSave(
            render: { _ in Data([1]) },
            makePanel: { panel },
            write: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        save.attach(to: owner)
        save.save(self.receipt) { outcome = $0 }
        panel.complete(URL(fileURLWithPath: "/unused-synthetic-receipt.png"))
        #expect(outcome == .failed)
        #expect(save.canSave)
    }

    @Test
    func `missing preview or failed rendering never presents a save panel`() {
        let owner = NSWindow()
        let panel = RecordingSavePanel()
        var outcomes: [CockpitReceiptImageSave.Outcome] = []
        let save = CockpitReceiptImageSave(render: { _ in nil }, makePanel: { panel })
        save.save(self.receipt) { outcomes.append($0) }
        save.attach(to: owner)
        save.save(self.receipt) { outcomes.append($0) }
        #expect(outcomes == [.failed, .failed])
        #expect(panel.beginCount == 0)
        #expect(!save.isSaving)
    }

    @Test
    func `removing the preview ends its save sheet and ignores late successful completion`() {
        let owner = NSWindow()
        let panel = RecordingSavePanel()
        var outcomes: [CockpitReceiptImageSave.Outcome] = []
        var writes = 0
        let save = CockpitReceiptImageSave(
            render: { _ in Data([1]) },
            makePanel: { panel },
            write: { _, _ in writes += 1 })
        save.attach(to: owner)
        save.save(self.receipt) { outcomes.append($0) }
        save.attach(to: nil)
        panel.complete(URL(fileURLWithPath: "/unused-synthetic-receipt.png"))
        #expect(panel.cancelCount == 1)
        #expect(outcomes == [.cancelled])
        #expect(writes == 0)
        #expect(!save.isSaving)
        #expect(!save.canSave)
    }

    @Test
    func `a cancelled request cannot complete or clear a newer save`() {
        let owner = NSWindow()
        let oldPanel = RecordingSavePanel()
        let newPanel = RecordingSavePanel()
        var panelCount = 0
        var outcomes: [CockpitReceiptImageSave.Outcome] = []
        var writes = 0
        let save = CockpitReceiptImageSave(
            render: { _ in Data([1]) },
            makePanel: {
                panelCount += 1
                return panelCount == 1 ? oldPanel : newPanel
            },
            write: { _, _ in writes += 1 })
        save.attach(to: owner)
        save.save(self.receipt) { outcomes.append($0) }
        save.attach(to: nil)
        save.attach(to: owner)
        save.save(self.receipt) { outcomes.append($0) }
        let destination = URL(fileURLWithPath: "/unused-synthetic-receipt.png")

        oldPanel.complete(destination)
        #expect(save.isSaving)
        #expect(writes == 0)
        #expect(outcomes == [.cancelled])
        newPanel.complete(destination)
        #expect(!save.isSaving)
        #expect(writes == 1)
        #expect(outcomes == [.cancelled, .saved])
    }

    @Test
    func `detaching after the weak owner is released still cancels its pending panel`() {
        weak var weakOwner: NSWindow?
        let panel = RecordingSavePanel()
        var outcome: CockpitReceiptImageSave.Outcome?
        let save = CockpitReceiptImageSave(render: { _ in Data([1]) }, makePanel: { panel })
        autoreleasepool {
            let owner = NSWindow()
            owner.isReleasedWhenClosed = false
            weakOwner = owner
            save.attach(to: owner)
            save.save(self.receipt) { outcome = $0 }
            owner.close()
        }
        #expect(weakOwner == nil)
        save.attach(to: nil)
        #expect(panel.cancelCount == 1)
        #expect(outcome == .cancelled)
        #expect(!save.isSaving)
    }

    @Test
    func `window reader reports the window containing the preview and clears it on removal`() async {
        let window = NSWindow()
        var reported: NSWindow?
        let reader = CockpitReceiptWindowView { reported = $0 }
        window.contentView = reader
        await Task.yield()
        #expect(reported === window)
        window.contentView = nil
        await Task.yield()
        #expect(reported == nil)
    }

    @Test
    func `a retained panel completion does not retain its save controller`() {
        let owner = NSWindow()
        let panel = RecordingSavePanel()
        var save: CockpitReceiptImageSave? = CockpitReceiptImageSave(
            render: { _ in Data([1]) },
            makePanel: { panel })
        weak var weakSave = save
        save?.attach(to: owner)
        save?.save(self.receipt) { _ in }
        save = nil
        #expect(weakSave == nil)
    }

    private var receipt: CockpitReceiptModel {
        CockpitReceiptModel(items: [], createdAt: Date(timeIntervalSince1970: 0), scopeLabel: "Synthetic test")
    }
}

@MainActor
private final class RecordingSavePanel: CockpitReceiptSavePanel {
    weak var owner: NSWindow?
    var beginCount = 0
    var cancelCount = 0
    private var completion: (@MainActor (URL?) -> Void)?

    func begin(on window: NSWindow, completion: @escaping @MainActor (URL?) -> Void) {
        self.owner = window
        self.beginCount += 1
        self.completion = completion
    }

    func complete(_ url: URL?) {
        let completion = self.completion
        self.completion = nil
        completion?(url)
    }

    func cancel() {
        self.cancelCount += 1
        // AppKit may deliver its completion after the view has already detached.
    }
}
