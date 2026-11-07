import AppKit
import SwiftUI

struct SSHConnectionInfoButton: NSViewRepresentable {
    let help: String

    func makeNSView(context: Context) -> SSHConnectionInfoControl {
        SSHConnectionInfoControl()
    }

    func updateNSView(_ button: SSHConnectionInfoControl, context: Context) {
        button.updateHelp(help)
    }

    static func dismantleNSView(_ button: SSHConnectionInfoControl, coordinator: ()) {
        button.closeHelp()
    }
}

/// An actual button and explicit mouse tracking make the instructions available
/// without depending on the system tooltip delay or an image's hit testing.
final class SSHConnectionInfoControl: NSButton, NSPopoverDelegate {
    private let helpPopover = NSPopover()
    private var helpView: SSHConnectionHelpHostingView?
    private var helpText = ""
    private var hoverArea: NSTrackingArea?
    private var closeTask: Task<Void, Never>?
    private var pointerInButton = false
    private var pointerInHelp = false
    private var pinned = false

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        contentTintColor = .secondaryLabelColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        target = self
        action = #selector(showOrPinHelp)
        helpPopover.behavior = .transient
        helpPopover.animates = false
        helpPopover.delegate = self
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }

    func updateHelp(_ text: String) {
        setAccessibilityLabel(L10n.string("support.ssh.connection_info"))
        setAccessibilityHelp(text)
        guard helpText != text else { return }
        helpText = text
        helpView?.rootView = SSHConnectionHelpView(help: text)
        if let helpView { helpPopover.contentSize = helpView.fittingSize }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInButton = true
        showHelp()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInButton = false
        closeAfterHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closeHelp() } else { updateTrackingAreas() }
    }

    @objc private func showOrPinHelp() {
        if helpPopover.isShown && pinned {
            closeHelp()
        } else {
            pinned = true
            showHelp()
        }
    }

    private func showHelp() {
        closeTask?.cancel()
        guard window != nil, !helpText.isEmpty, !helpPopover.isShown else { return }
        let view = SSHConnectionHelpHostingView(rootView: SSHConnectionHelpView(help: helpText))
        view.hoverChanged = { [weak self] hovering in
            guard let self else { return }
            self.pointerInHelp = hovering
            if hovering { self.closeTask?.cancel() } else { self.closeAfterHover() }
        }
        let controller = NSViewController()
        controller.view = view
        helpView = view
        helpPopover.contentViewController = controller
        helpPopover.contentSize = view.fittingSize
        helpPopover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    private func closeAfterHover() {
        closeTask?.cancel()
        guard !pinned else { return }
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self,
                  !self.pointerInButton, !self.pointerInHelp, !self.pinned else { return }
            self.helpPopover.performClose(nil)
        }
    }

    func closeHelp() {
        closeTask?.cancel()
        helpPopover.close()
        pinned = false
        pointerInButton = false
        pointerInHelp = false
    }

    func popoverDidClose(_ notification: Notification) {
        closeTask?.cancel()
        pinned = false
        pointerInHelp = false
    }
}

private struct SSHConnectionHelpView: View {
    let help: String

    var body: some View {
        Text(help)
            .font(UtilityStyle.body)
            .textSelection(.enabled)
            .frame(width: 360, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
    }
}

private final class SSHConnectionHelpHostingView: NSHostingView<SSHConnectionHelpView> {
    var hoverChanged: (Bool) -> Void = { _ in }
    private var hoverArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { updateTrackingAreas() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }
}
