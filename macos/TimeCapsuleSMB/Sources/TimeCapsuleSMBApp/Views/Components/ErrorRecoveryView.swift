import AppKit
import SwiftUI

struct ErrorBlock: View {
    let presentation: RecoveryGuidancePresentation
    private let title: String

    init(error: BackendErrorViewModel) {
        presentation = RecoveryGuidancePresentation(error: error)
        title = UtilityErrorPresentation.title(for: error)
    }

    init(presentation: RecoveryGuidancePresentation) {
        self.presentation = presentation
        title = presentation.title
    }

    var body: some View {
        Label(title, systemImage: "exclamationmark.circle")
            .font(UtilityStyle.body).foregroundStyle(.red)
    }
}

struct ErrorRecoveryView: View {
    let error: BackendErrorViewModel
    let guidance: String?
    let diagnosticsText: (() -> String)?
    let omittedActions: [RecoveryActionKind]
    let perform: (RecoveryActionKind) -> (() -> Void)?

    init(error: BackendErrorViewModel, guidance: String? = nil, diagnosticsText: (() -> String)? = nil,
         omittedActions: [RecoveryActionKind] = [], perform: @escaping (RecoveryActionKind) -> (() -> Void)?) {
        self.error = error
        self.guidance = guidance
        self.diagnosticsText = diagnosticsText
        self.omittedActions = omittedActions
        self.perform = perform
    }

    var body: some View {
        let presentation = RecoveryGuidancePresentation(error: error, localNetworkFacts: .current())
        let actions = RecoveryActionMapper.actions(for: error) { perform($0) != nil }
            .filter { !omittedActions.contains($0.kind) }
        let primary = actions.first { $0.kind != .copyDiagnostics && $0.kind != .diagnostics }
        VStack(alignment: .leading, spacing: 12) {
            ErrorBlock(error: error)
            if let guidance { Text(guidance).foregroundStyle(.red) }
            if let key = error.recovery?.localizationKey,
               key.contains("disk_failing") || key.contains("disk_unreadable"), let message = presentation.message {
                Text(message).foregroundStyle(.red)
            }
            if let primary {
                Button(UtilityErrorPresentation.actionTitle(primary)) { perform(primary.kind)?() }
            }
            DashboardDisclosureSection(title: L10n.string("utility.details")) {
                if presentation.title != UtilityErrorPresentation.title(for: error) { Text(presentation.title) }
                if let message = presentation.message { Text(message) }
                ForEach(Array(presentation.steps.enumerated()), id: \.offset) { _, step in Text(step) }
                if let details = presentation.details { Text(details).textSelection(.enabled) }
                HStack(spacing: 8) {
                    ForEach(actions.filter { $0.id != primary?.id && $0.kind != .copyDiagnostics }) { action in
                        Button(UtilityErrorPresentation.actionTitle(action)) { perform(action.kind)?() }
                    }
                    Button(L10n.string("utility.copy_details"), action: copyDiagnostics)
                }
            }
            .font(UtilityStyle.secondary).foregroundStyle(.secondary)
        }
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsText?() ?? "\(error.operation) \(error.code): \(error.diagnosticMessage ?? error.message)", forType: .string)
    }
}
