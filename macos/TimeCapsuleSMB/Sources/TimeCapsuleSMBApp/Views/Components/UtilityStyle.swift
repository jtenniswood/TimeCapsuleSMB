import AppKit
import SwiftUI

/// AirPort Utility uses the standard Mac control font, rather than a web-style
/// hierarchy of large headings and cards. Keep these sizes shared by every pane.
enum UtilityStyle {
    static let body = Font.system(size: NSFont.systemFontSize)
    static let secondary = Font.system(size: NSFont.smallSystemFontSize)
    static let heading = Font.system(size: NSFont.systemFontSize, weight: .semibold)
    static let title = Font.system(size: 17, weight: .semibold)
    static let deviceName = Font.system(size: 17, weight: .bold)
    static let panePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 12
    static let fieldWidth: CGFloat = 320
    static let windowBackground = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.14 : 0.925, alpha: 1)
    }
    static let paneBackground = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.16 : 0.965, alpha: 1)
    }
    static let paneBorder = NSColor(name: nil) { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.29 : 0.74, alpha: 1)
    }
}

struct UtilityPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UtilityStyle.sectionSpacing, content: content)
                .padding(UtilityStyle.panePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct UtilityNotice<Content: View>: View {
    var symbol = "exclamationmark.triangle.fill"
    var color = Color.orange
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6, content: content)
        }
        .font(UtilityStyle.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UtilityFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8, content: content)
            .font(UtilityStyle.body)
            .controlSize(.regular)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }
}

struct UtilityFormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).multilineTextAlignment(.trailing).frame(width: 160, alignment: .trailing)
            content().frame(maxWidth: UtilityStyle.fieldWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(UtilityStyle.body)
    }
}
