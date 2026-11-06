import SwiftUI

/// The same native pane controls and spacing in the utility and Settings.
struct UtilityTabs<Selection: Hashable, Content: View>: View {
    let tabs: [(id: Selection, title: String)]
    @Binding var selection: Selection
    @ViewBuilder let content: (Selection) -> Content

    var body: some View {
        VStack(spacing: -12) {
            Picker(L10n.string("simple.device_settings"), selection: $selection) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in Text(tab.title).tag(tab.id) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.horizontal, 4)
            .background(Color(nsColor: .windowBackgroundColor))
            .zIndex(1)
            GroupBox {
                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 12)
            }
        }
        .font(UtilityStyle.body)
    }
}
