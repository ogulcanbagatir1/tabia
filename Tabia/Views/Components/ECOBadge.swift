import SwiftUI

struct ECOBadge: View {
    let eco: String
    var color: Color = DS.accent

    var body: some View {
        Text(eco)
            .font(AnnFont.mono(10, bold: true))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color)
            .cornerRadius(3)
    }
}
