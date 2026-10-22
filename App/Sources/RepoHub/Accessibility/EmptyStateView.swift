import SwiftUI

/// An empty, error, or signed-out state: like `ContentUnavailableView`, whose
/// gray text fails WCAG AA contrast, but readable (#58).
struct EmptyStateView<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text
    let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            description
                .foregroundStyle(.secondaryText)
                .multilineTextAlignment(.center)
            actions
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}
