import AppKit
import CodexBarCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CockpitReceiptPreview: View {
    let receipt: CockpitReceiptModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = L("cockpit_ui_preview_note")

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L("cockpit_ui_preview_title")).font(.headline)
                Spacer()
                Button(L("cockpit_ui_done")) { self.dismiss() }.keyboardShortcut(.cancelAction)
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
                    if ShareStatsExporter.saveImage(self.receipt) { self.message = L("cockpit_ui_saved") }
                } label: {
                    Label(L("cockpit_ui_save_png"), systemImage: "square.and.arrow.down")
                }
                Spacer()
                Text(self.message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 700, height: 680)
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

    static func saveImage(_ receipt: CockpitReceiptModel) -> Bool {
        guard let data = ShareStatsRenderer.pngData(for: receipt) else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "codexbar-cockpit-receipt.png"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }
}
