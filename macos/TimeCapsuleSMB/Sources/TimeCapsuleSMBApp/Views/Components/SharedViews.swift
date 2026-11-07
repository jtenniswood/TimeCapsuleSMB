import SwiftUI

struct WarningBanner: View {
    let warning: HostCompatibilityWarning

    var body: some View {
        UtilityNotice {
                Text(warning.title)
                    .font(UtilityStyle.heading)
                DashboardDisclosureSection(title: L10n.string("utility.details")) {
                    Text(warning.message).foregroundStyle(.secondary)
                }
        }
    }
}

struct SummaryGrid: View {
    let rows: [(String, String)]
    var valueLineLimit: Int? = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160, alignment: .trailing)
                    Text(row.1)
                        .lineLimit(valueLineLimit)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(UtilityStyle.body)
    }
}

struct StageLine: View {
    let stage: OperationStageState

    var body: some View {
        HStack(spacing: 8) {
            Text(OperationTimelineBuilder.stageTitle(for: stage.operation, stage: stage.stage))
                .font(UtilityStyle.secondary)
            if let detail = stage.progressDetail
                ?? OperationTimelineBuilder.stageDetail(for: stage.operation, stage: stage.stage) {
                Text(detail)
                    .font(UtilityStyle.secondary)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DashboardDisclosureSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.top, 12)
            .padding(.leading, 16)
        }
        .font(UtilityStyle.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
