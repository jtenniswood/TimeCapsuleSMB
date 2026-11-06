import SwiftUI

/// Use the platform tab view without custom tab drawing or layout.
struct UtilityTabs<Selection: Hashable, Content: View>: View {
    let tabs: [(id: Selection, title: String)]
    @Binding var selection: Selection
    @ViewBuilder let content: (Selection) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                content(tab.id)
                    .tabItem { Text(tab.title) }
                    .tag(tab.id)
            }
        }
        .tabViewStyle(.automatic)
        .font(UtilityStyle.body)
    }
}
