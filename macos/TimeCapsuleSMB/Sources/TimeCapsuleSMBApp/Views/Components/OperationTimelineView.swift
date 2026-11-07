import SwiftUI

struct OperationTimelineListView: View {
    let title: String?
    let emptyMessage: String?
    let items: [OperationTimelineItem]
    let showsRowBackground: Bool

    init(
        title: String? = nil,
        emptyMessage: String? = nil,
        items: [OperationTimelineItem],
        showsRowBackground: Bool = true
    ) {
        self.title = title
        self.emptyMessage = emptyMessage
        self.items = items
        self.showsRowBackground = showsRowBackground
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(UtilityStyle.heading)
            }

            if items.isEmpty {
                if let emptyMessage {
                    Text(emptyMessage)
                        .font(UtilityStyle.secondary)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        OperationTimelineRow(item: item, showsBackground: showsRowBackground)
                            .transition(rowTransition)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: items)
    }

    private var rowTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .top))
    }
}

struct OperationTimelineRow: View {
    let item: OperationTimelineItem
    let showsBackground: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: OperationTimelineItem, showsBackground: Bool = true) {
        self.item = item
        self.showsBackground = showsBackground
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            OperationTimelineStateIcon(state: item.state)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                AnimatedProgressText(message: item.title, isRunning: item.state == .running && !hasDetail)
                    .font(UtilityStyle.body)
                    .foregroundStyle(.primary)
                if let detail = item.detail, !detail.isEmpty {
                    AnimatedProgressText(message: detail, isRunning: item.state == .running)
                        .font(UtilityStyle.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let start = item.elapsedSince, item.state == .running {
                    TimelineView(.periodic(from: start, by: 15)) { context in
                        Text(OperationTimelineBuilder.elapsedText(since: start, now: context.date))
                            .font(UtilityStyle.secondary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(UtilityStyle.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: item.state)
        .accessibilityElement(children: .combine)
    }

    private var hasDetail: Bool {
        item.detail?.isEmpty == false
    }

}
