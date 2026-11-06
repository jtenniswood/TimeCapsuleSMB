import SwiftUI

struct BlockingProgressOverlay<Progress: BlockingProgressPresenting>: View {
    let progress: Progress
    let allowsBackgroundInteraction: Bool

    init(progress: Progress, allowsBackgroundInteraction: Bool = false) {
        self.progress = progress
        self.allowsBackgroundInteraction = allowsBackgroundInteraction
    }

    var body: some View {
        ZStack {
            if !allowsBackgroundInteraction { Color.clear.contentShape(Rectangle()).ignoresSafeArea() }
            VStack(spacing: 16) {
                ProgressView().controlSize(.regular)
                Text(progress.title).font(UtilityStyle.body)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!allowsBackgroundInteraction)
    }
}

/// The transcript stays in Details; progress has one stable, readable line.
struct InlineOperationProgress<Progress: BlockingProgressPresenting>: View {
    let progress: Progress
    var title: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(title ?? progress.title)
        }
        .font(UtilityStyle.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(progress.message)
    }
}
