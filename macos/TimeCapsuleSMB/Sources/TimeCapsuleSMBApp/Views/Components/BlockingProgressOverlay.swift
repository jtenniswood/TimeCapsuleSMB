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
            if !allowsBackgroundInteraction {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
            }

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(progress.title)
                    .font(.headline)
                Text(progress.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(progress.detail ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 28, alignment: .top)
                    .opacity(progress.detail?.isEmpty == false ? 1 : 0)
            }
            .padding(22)
            .frame(width: 340)
            .frame(minHeight: 176)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(!allowsBackgroundInteraction)
        .transition(.opacity)
    }
}

/// Progress stays in the page so its controls, warnings and Cancel remain clear.
struct InlineOperationProgress<Progress: BlockingProgressPresenting>: View {
    let progress: Progress
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 5) {
                Text(progress.title).fontWeight(.medium)
                Text(progress.message).foregroundStyle(.secondary)
                if let detail = progress.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
