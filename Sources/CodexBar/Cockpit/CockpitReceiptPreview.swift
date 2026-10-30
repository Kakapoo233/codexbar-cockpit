import AppKit
import CodexBarCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CockpitReceiptPreview: View {
    let receipt: CockpitReceiptModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = L("cockpit_ui_preview_note")
    @State private var imageSave = CockpitReceiptImageSave()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L("cockpit_ui_preview_title")).font(.headline)
                Spacer()
                Button(L("cockpit_ui_done")) { self.dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(self.imageSave.isSaving)
            }
            ScrollView {
                CockpitReceiptCardView(receipt: self.receipt)
            }
            .background(Color.gray.opacity(0.08))
            HStack {
                Button {
                    self.message = ShareStatsExporter
                        .copyImage(self.receipt) ? L("cockpit_ui_copied") : L("cockpit_ui_export_error")
                } label: {
                    Label(L("cockpit_ui_copy_png"), systemImage: "photo.on.rectangle")
                }
                Button {
                    self.imageSave.save(self.receipt) { outcome in
                        switch outcome {
                        case .saved: self.message = L("cockpit_ui_saved")
                        case .failed: self.message = L("cockpit_ui_export_error")
                        case .cancelled: break
                        }
                    }
                } label: {
                    Label(L("cockpit_ui_save_png"), systemImage: "square.and.arrow.down")
                }
                .disabled(!self.imageSave.canSave)
                Spacer()
                Text(self.message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 700, height: 680)
        .background(CockpitReceiptWindowReader { self.imageSave.attach(to: $0) })
        .onDisappear { self.imageSave.attach(to: nil) }
    }
}

/// A bounded paper layout; long selections retain their complete totals and disclose truncated rows.
struct CockpitReceiptCardView: View {
    static let width: CGFloat = 620
    static let visibleItemLimit = 60
    let receipt: CockpitReceiptModel

    static func size(for receipt: CockpitReceiptModel) -> CGSize {
        CGSize(
            width: self.width,
            height: CGFloat(390 + min(receipt.items.count, self.visibleItemLimit) * 78 + receipt.totals.count * 92))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            Divider().padding(.vertical, 20)
            ForEach(self.receipt.items.prefix(Self.visibleItemLimit)) { item in
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                        Text(item.providerName + (item.sessionCount > 1 ? L(
                            "cockpit_ui_session_count",
                            item.sessionCount) : ""))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(self.costText(
                            item.estimatedCost,
                            currency: item.currencyCode,
                            partial: item.costIsPartial))
                        Text(L("cockpit_ui_tokens_value", self.tokenText(item.tokens, partial: item.tokensArePartial)))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .frame(height: 78, alignment: .top)
            }
            if self.receipt.items.count > Self.visibleItemLimit {
                Text(L("cockpit_ui_truncated_rows", self.receipt.items.count - Self.visibleItemLimit))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 16)
            ForEach(self.receipt.totals) { total in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(total.costIsPartial ? L("cockpit_ui_known_cost", total.currencyCode) : L(
                            "cockpit_ui_cost_total",
                            total.currencyCode))
                        Spacer()
                        Text(self.costText(total.knownCost, currency: total.currencyCode, partial: total.costIsPartial))
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text(total.tokensArePartial ? L("cockpit_ui_known_tokens") : L("cockpit_ui_token_total"))
                        Spacer()
                        Text(self.tokenText(total.knownTokens, partial: total.tokensArePartial)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(height: 92, alignment: .top)
            }
            self.footer
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: Self.width, height: Self.size(for: self.receipt).height, alignment: .topLeading)
        .foregroundStyle(Color(red: 0.13, green: 0.15, blue: 0.18))
        .background(Color(red: 0.99, green: 0.98, blue: 0.95))
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "receipt").font(.title2)
                Text(L("cockpit_ui_brand_receipt")).font(.system(size: 20, weight: .bold, design: .monospaced))
            }
            Text(L("cockpit_ui_receipt_task_count", self.receipt.items.count))
            Text(self.receipt.scopeLabel).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(self.receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if self.receipt.totals.contains(where: { $0.costIsPartial || $0.tokensArePartial }) {
                Text(L("cockpit_ui_partial_cost_note"))
            }
            if self.receipt.items.contains(where: \.lineageIsPartial) {
                Text(L("cockpit_ui_partial_task_note"))
            }
            Text(L("cockpit_ui_cost_note"))
            Text(L("cockpit_ui_date_note"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func costText(_ cost: Double?, currency: String, partial: Bool) -> String {
        guard let cost else { return L("cockpit_ui_unknown") }
        return (partial ? "≥ " : "") + UsageFormatter.currencyString(cost, currencyCode: currency)
    }

    private func tokenText(_ tokens: Int?, partial: Bool) -> String {
        guard let tokens else { return L("cockpit_ui_unknown") }
        return (partial ? "≥ " : "") + UsageFormatter.tokenCountString(tokens)
    }
}

extension ShareStatsRenderer {
    /// Uses the same native, offline bitmap path as the existing share card.
    static func pngData(for receipt: CockpitReceiptModel) -> Data? {
        let size = CockpitReceiptCardView.size(for: receipt)
        let view = NSHostingView(rootView: CockpitReceiptCardView(receipt: receipt))
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: representation)
        else { return nil }
        representation.size = size
        view.displayIgnoringOpacity(view.bounds, in: context)
        return representation.representation(using: .png, properties: [:])
    }
}

extension ShareStatsExporter {
    static func copyImage(_ receipt: CockpitReceiptModel, pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = ShareStatsRenderer.pngData(for: receipt) else { return false }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

@MainActor
protocol CockpitReceiptSavePanel: AnyObject {
    func begin(on window: NSWindow, completion: @escaping @MainActor (URL?) -> Void)
    func cancel()
}

/// Keeps PNG saving scoped to the preview's own sheet, without an application-modal run loop.
@MainActor
@Observable
final class CockpitReceiptImageSave {
    enum Outcome: Equatable { case saved, cancelled, failed }

    private(set) var isSaving = false
    private(set) var hasWindow = false
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var pending: Request?
    private let render: @MainActor (CockpitReceiptModel) -> Data?
    private let makePanel: @MainActor () -> any CockpitReceiptSavePanel
    private let write: @MainActor (Data, URL) throws -> Void

    private struct Request {
        let id: UUID
        let panel: any CockpitReceiptSavePanel
        let completion: @MainActor (Outcome) -> Void
    }

    init(
        render: @escaping @MainActor (CockpitReceiptModel) -> Data? = ShareStatsRenderer.pngData,
        makePanel: @escaping @MainActor () -> any CockpitReceiptSavePanel = { CockpitReceiptNativeSavePanel() },
        write: @escaping @MainActor (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) })
    {
        self.render = render
        self.makePanel = makePanel
        self.write = write
    }

    var canSave: Bool {
        self.hasWindow && !self.isSaving
    }

    func attach(to window: NSWindow?) {
        if window == nil || self.window !== window { self.cancel() }
        self.window = window
        self.hasWindow = window != nil
    }

    func save(_ receipt: CockpitReceiptModel, completion: @escaping @MainActor (Outcome) -> Void) {
        guard !self.isSaving else { return }
        guard let window = self.window, let data = self.render(receipt) else {
            completion(.failed)
            return
        }
        let request = Request(id: UUID(), panel: self.makePanel(), completion: completion)
        let requestID = request.id
        self.pending = request
        self.isSaving = true
        request.panel.begin(on: window) { [weak self] url in
            guard let self, self.pending?.id == requestID else { return }
            self.pending = nil
            self.isSaving = false
            guard let url else {
                completion(.cancelled)
                return
            }
            do {
                try self.write(data, url)
                completion(.saved)
            } catch {
                completion(.failed)
            }
        }
    }

    func cancel() {
        guard let request = self.pending else { return }
        self.pending = nil
        self.isSaving = false
        request.panel.cancel()
        request.completion(.cancelled)
    }
}

@MainActor
private final class CockpitReceiptNativeSavePanel: CockpitReceiptSavePanel {
    private let panel = NSSavePanel()
    private weak var owner: NSWindow?

    func begin(on window: NSWindow, completion: @escaping @MainActor (URL?) -> Void) {
        self.owner = window
        self.panel.allowedContentTypes = [.png]
        self.panel.canCreateDirectories = true
        self.panel.nameFieldStringValue = "codexbar-cockpit-receipt.png"
        self.panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.owner = nil
            completion(response == .OK ? self.panel.url : nil)
        }
    }

    func cancel() {
        self.owner?.endSheet(self.panel, returnCode: .cancel)
        self.panel.orderOut(nil)
        self.owner = nil
    }
}

private struct CockpitReceiptWindowReader: NSViewRepresentable {
    let onWindowChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> CockpitReceiptWindowView {
        CockpitReceiptWindowView(onWindowChange: self.onWindowChange)
    }

    func updateNSView(_ nsView: CockpitReceiptWindowView, context: Context) {}

    static func dismantleNSView(_ nsView: CockpitReceiptWindowView, coordinator: ()) {
        nsView.onWindowChange(nil)
        nsView.onWindowChange = { _ in }
    }
}

@MainActor
final class CockpitReceiptWindowView: NSView {
    var onWindowChange: @MainActor (NSWindow?) -> Void

    init(onWindowChange: @escaping @MainActor (NSWindow?) -> Void) {
        self.onWindowChange = onWindowChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onWindowChange(self.window)
        }
    }
}
