import SwiftUI

/// Native button activation remains available for keyboard and accessibility actions.
@MainActor
struct CockpitPanelPageButton: View {
    let page: CockpitPanelPage
    @Bindable var navigation: CockpitPanelNavigation
    let showsTitle: Bool

    var body: some View {
        Button {
            self.selectPage()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: self.page.symbol)
                if self.showsTitle { Text(self.page.title) }
            }
            .font(.system(size: 13, weight: self.navigation.page == self.page ? .semibold : .regular))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background(
                self.navigation.page == self.page ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(CockpitPagePressButtonStyle(onPress: self.selectPage))
        .help(self.page.title)
        .accessibilityLabel(self.page.title)
        .accessibilityIdentifier("cockpit-panel-page-\(self.page.rawValue)")
        .accessibilityAddTraits(self.navigation.page == self.page ? .isSelected : [])
    }

    private func selectPage() {
        // Mouse-up and keyboard activation share the same idempotent navigation setter.
        self.navigation.page = self.page
    }
}

private struct CockpitPagePressButtonStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { self.onPress() }
            }
    }
}
