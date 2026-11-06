import AppKit
import SwiftUI

/// A standard rounded Mac segmented control above a standard inset group box.
/// SwiftUI owns the selected pane, so changing tabs cannot leave an old pane attached.
struct UtilityTabs<Selection: Hashable, Content: View>: View {
    let tabs: [(id: Selection, title: String)]
    @Binding var selection: Selection
    @ViewBuilder let content: (Selection) -> Content

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                UtilityPaneBezel().allowsHitTesting(false)
                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 12)
            }
            .padding(.top, 12)
            NativePanePicker(tabs: tabs, selection: $selection)
                .fixedSize()
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlColor)))
        }
        .font(UtilityStyle.body)
    }
}

struct NativePanePicker<Selection: Hashable>: NSViewRepresentable {
    let tabs: [(id: Selection, title: String)]
    @Binding var selection: Selection

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.cell = AirPortSegmentCell()
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.controlSize = .regular
        control.font = .systemFont(ofSize: NSFont.systemFontSize)
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.isEnabled = context.environment.isEnabled
        control.segmentCount = tabs.count
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        for (index, tab) in tabs.enumerated() {
            control.setLabel(tab.title, forSegment: index)
            // Explicit native segment widths prevent compression to zero when
            // AppKit is measured by SwiftUI before its first window layout.
            let width = ceil((tab.title as NSString).size(withAttributes: [.font: font]).width) + 28
            control.setWidth(width, forSegment: index)
        }
        control.selectedSegment = tabs.firstIndex { $0.id == selection } ?? -1
        control.sizeToFit()
        control.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: max(nsView.intrinsicContentSize.width, (0..<nsView.segmentCount).reduce(4) { $0 + nsView.width(forSegment: $1) }),
               height: max(24, nsView.intrinsicContentSize.height))
    }

    final class Coordinator: NSObject {
        var parent: NativePanePicker
        init(parent: NativePanePicker) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.tabs.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.tabs[sender.selectedSegment].id
        }
    }
}

private struct UtilityPaneBezel: NSViewRepresentable {
    func makeNSView(context: Context) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = UtilityStyle.paneBackground
        box.borderColor = UtilityStyle.paneBorder
        box.borderWidth = 1
        box.cornerRadius = 6
        box.titlePosition = .noTitle
        box.contentViewMargins = .zero
        return box
    }
    func updateNSView(_ nsView: NSBox, context: Context) {}
}

/// The native segmented control retains its focus, hit testing and accessibility.
/// Only the selected cell's finish follows AirPort Utility's older beveled style.
private final class AirPortSegmentCell: NSSegmentedCell {
    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        guard isSelected(forSegment: segment), isEnabled else {
            super.drawSegment(segment, inFrame: frame, with: controlView)
            return
        }
        let dark = controlView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rect = frame.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        let top = NSColor(white: dark ? 0.27 : 1, alpha: 1)
        let bottom = NSColor(white: dark ? 0.18 : 0.88, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)
        NSColor(white: 0, alpha: dark ? 0.6 : 0.25).setStroke()
        path.lineWidth = 1
        path.stroke()
        let text = NSAttributedString(string: label(forSegment: segment) ?? "", attributes: [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }
}
