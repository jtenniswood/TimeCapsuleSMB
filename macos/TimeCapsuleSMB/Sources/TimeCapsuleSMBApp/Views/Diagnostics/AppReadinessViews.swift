import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppReadinessBannerView: View {
    @ObservedObject var store: AppReadinessStore
    let showDiagnostics: () -> Void

    var body: some View {
        switch store.state {
        case .idle, .ready, .blocked:
            EmptyView()
        case .resolvingBundle, .checkingVersion, .checkingCapabilities, .validatingInstall:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L10n.string("utility.readiness.opening"))
                Spacer()
            }
            .font(UtilityStyle.secondary)
            .padding(.horizontal, 24).padding(.vertical, 8)
        case .degraded:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(L10n.string("utility.readiness.warning"))
                Spacer()
                Button(L10n.string("utility.support"), action: showDiagnostics)
            }
            .font(UtilityStyle.body)
            .padding(.horizontal, 24).padding(.vertical, 8)
        }
    }
}

struct AppReadinessBlockedView: View {
    @ObservedObject var store: AppReadinessStore
    let showDiagnostics: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(L10n.string("utility.readiness.blocked")).font(UtilityStyle.title)
            HStack(spacing: 8) {
                Button(L10n.string("utility.support"), action: showDiagnostics)
                Button(L10n.string("utility.try_again")) { store.start() }
                    .disabled(!store.canRetry).keyboardShortcut(.defaultAction)
            }
        }
        .font(UtilityStyle.body)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppDiagnosticsView: View {
    @ObservedObject var store: AppReadinessStore
    let exportContext: (_ includeBackendEvents: Bool) -> DiagnosticsExportContext
    @Binding var showBackendEvents: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var exportStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("utility.support.title")).font(UtilityStyle.title)
                .padding(.horizontal, 24).padding(.top, 24)
            ScrollView {
                Text(exportText())
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))
            .padding(.horizontal, 24)
            Toggle(L10n.string("utility.support.include_logs"), isOn: $showBackendEvents)
                .padding(.horizontal, 24)
            UtilityFooter {
                if let exportStatus { Text(exportStatus).font(UtilityStyle.secondary).foregroundStyle(.secondary) }
                Spacer()
                Button(L10n.string("diagnostics.copy"), action: copyDiagnostics)
                Button(L10n.string("diagnostics.save"), action: saveDiagnostics)
                Button(L10n.string("action.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .font(UtilityStyle.body)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 460, idealHeight: 520)
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exportText(), forType: .string)
        exportStatus = L10n.string("diagnostics.copied")
    }

    private func saveDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Time Capsule Updater Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        let text = exportText()
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                Task { @MainActor in
                    exportStatus = L10n.string("diagnostics.saved")
                }
            } catch {
                Task { @MainActor in
                    exportStatus = error.localizedDescription
                }
            }
        }
    }

    func exportText() -> String {
        DiagnosticsExportBuilder().build(context: exportContext(showBackendEvents))
    }
}


struct EventList: View {
    let events: [BackendEvent]

    var body: some View {
        List(events) { event in
            VStack(alignment: .leading, spacing: 4) {
                // Diagnostics stay in the helper's English.
                Text(event.logLine)
                    .font(.system(size: 11, design: .monospaced))
                if let payload = event.payload, event.type == "result" {
                    Text(payload.displayText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
            }
            .padding(.vertical, 3)
        }
    }
}
