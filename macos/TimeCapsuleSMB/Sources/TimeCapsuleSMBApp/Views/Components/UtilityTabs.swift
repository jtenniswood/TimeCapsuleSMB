import SwiftUI

/// Keep pane navigation in the content area using the standard Mac control.
/// No toolbar tabs, custom drawing, backgrounds or selection overlays.
struct UtilityTabs<Selection: Hashable, Content: View>: View {
    let tabs: [(id: Selection, title: String)]
    @Binding var selection: Selection
    @ViewBuilder let content: (Selection) -> Content

    var body: some View {
        VStack(spacing: 16) {
            Picker(L10n.string("simple.device_settings"), selection: $selection) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                    Text(tab.title).tag(tab.id)
                }
            }
            .pickerStyle(.palette)
            .labelsHidden()
            .controlSize(.regular)
            .frame(width: CGFloat(tabs.count) * 120)

            GroupBox {
                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .font(UtilityStyle.body)
    }
}
