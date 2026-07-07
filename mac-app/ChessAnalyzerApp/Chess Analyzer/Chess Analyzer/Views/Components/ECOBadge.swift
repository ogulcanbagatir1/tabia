import SwiftUI

struct ECOBadge: View {
    let eco: String
    var color: Color = DS.accent

    var body: some View {
        Text(eco)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color)
            .cornerRadius(3)
    }
}
