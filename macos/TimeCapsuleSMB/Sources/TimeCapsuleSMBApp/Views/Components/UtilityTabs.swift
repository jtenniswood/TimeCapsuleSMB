import AppKit
import SwiftUI

/// AppKit owns the tab strip, bezel, keyboard navigation and accessibility.
/// Hosting only the selected pane also keeps hidden panes from starting work.
struct UtilityTabs<Selection: Hashable, Content: View>: NSViewRepresentable {
    let tabs: [(id: Selection, title: String)]
    @Binding var selection: Selection
    @ViewBuilder let content: (Selection) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTabView {
        let view = NSTabView()
        view.tabViewType = .topTabsBezelBorder
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.controlSize = .regular
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTabView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        if coordinator.ids != tabs.map(\.id) {
            coordinator.clearHostedPane()
            view.tabViewItems.forEach(view.removeTabViewItem)
            coordinator.ids = tabs.map(\.id)
            for (index, tab) in tabs.enumerated() {
                let item = NSTabViewItem(identifier: index)
                item.label = tab.title
                view.addTabViewItem(item)
            }
        }
        for (index, tab) in tabs.enumerated() { view.tabViewItem(at: index).label = tab.title }
        guard let index = tabs.firstIndex(where: { $0.id == selection }) else { return }
        coordinator.showPane(at: index, in: view)
        if view.selectedTabViewItem.map({ view.indexOfTabViewItem($0) }) != index { view.selectTabViewItem(at: index) }
    }

    final class Coordinator: NSObject, NSTabViewDelegate {
        var parent: UtilityTabs
        var ids: [Selection] = []
        var isUpdating = false
        private var host: NSHostingView<AnyView>?
        private var hostedIndex: Int?

        init(parent: UtilityTabs) { self.parent = parent }

        func clearHostedPane() { host = nil; hostedIndex = nil }

        func showPane(at index: Int, in view: NSTabView) {
            let root = AnyView(parent.content(ids[index]).font(UtilityStyle.body).controlSize(.regular))
            if hostedIndex == index, let host {
                host.rootView = root
            } else {
                if let hostedIndex, hostedIndex < view.numberOfTabViewItems {
                    view.tabViewItem(at: hostedIndex).view = nil
                }
                let host = NSHostingView(rootView: root)
                host.autoresizingMask = [.width, .height]
                view.tabViewItem(at: index).view = host
                self.host = host
                hostedIndex = index
            }
        }

        func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            guard !isUpdating, let tabViewItem else { return }
            let index = tabView.indexOfTabViewItem(tabViewItem)
            guard ids.indices.contains(index) else { return }
            showPane(at: index, in: tabView)
            parent.selection = ids[index]
        }
    }
}
