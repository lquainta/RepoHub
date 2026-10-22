import AppKit
import SwiftUI

extension ShapeStyle where Self == SecondaryTextStyle {
    /// Secondary text that meets WCAG AA contrast (4.5:1) (#58). See ``SecondaryTextStyle``.
    static var secondaryText: SecondaryTextStyle { SecondaryTextStyle() }
}

/// Secondary text that meets WCAG AA contrast (4.5:1) in light and dark mode
/// and on selected rows (#58). The system `.secondary` style is about 3.9:1 on
/// a window background. This opaque gray is about 8:1 in light mode and 10:1
/// in dark mode, still visibly lighter than primary text; with Increase
/// Contrast, and on a selected row's highlight, it's the primary color.
struct SecondaryTextStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.backgroundProminence == .increased ? Color.primary : Self.gray
    }

    private static let gray = Color(
        nsColor: NSColor(name: "RepoHubSecondaryText") { appearance in
            switch appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ]) {
            case .darkAqua: NSColor(white: 0.78, alpha: 1)
            case .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua: .labelColor
            default: NSColor(white: 0.32, alpha: 1)
            }
        }
    )
}

/// A label whose icon carries the status color while the text stays readable:
/// orange, green, and red text fail WCAG AA contrast on light backgrounds (#58).
struct StatusLabel: View {
    let title: Text
    let systemImage: String
    let tint: Color
    @Environment(\.backgroundProminence) private var prominence

    init(_ title: Text, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color) {
        self.init(Text(title), systemImage: systemImage, tint: tint)
    }

    var body: some View {
        Label {
            title
        } icon: {
            // On a selected row's highlight, colored icons lose contrast.
            Image(systemName: systemImage).foregroundStyle(prominence == .increased ? Color.primary : tint)
        }
    }
}
