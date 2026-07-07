import SwiftUI

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(DS.textTertiary)
            .kerning(0.8)
            .padding(.horizontal, 0)
    }
}
