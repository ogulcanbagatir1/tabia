import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var description: String? = nil
    var iconSize: CGFloat = 40
    var titleSize: CGFloat = 14
    var descriptionSize: CGFloat = 12
    var descriptionWidth: CGFloat = 200
    var spacing: CGFloat = 12
    var padding: CGFloat = 24

    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundColor(DS.ink40)

            VStack(spacing: 6) {
                Text(title)
                    .font(AnnFont.serif(titleSize, .semibold))
                    .foregroundColor(DS.ink60)

                if let description = description {
                    Text(description)
                        .font(AnnFont.serif(descriptionSize))
                        .foregroundColor(DS.ink40)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: descriptionWidth)
                }
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
