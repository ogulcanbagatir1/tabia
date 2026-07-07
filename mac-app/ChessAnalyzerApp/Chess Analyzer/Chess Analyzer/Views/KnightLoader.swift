import SwiftUI

/// On-brand loading animation: a chess knight that hops in place with squash-and-stretch and a
/// shrinking shadow. Drop-in replacement for a plain `ProgressView()` spinner anywhere in the app.
struct KnightLoader: View {
    var size: CGFloat = 46
    var tint: Color = DS.accent
    var showShadow: Bool = true

    @State private var hop = false

    var body: some View {
        VStack(spacing: size * 0.14) {
            Text("♞")
                .font(.system(size: size))
                .foregroundColor(tint)
                // squash on the ground, stretch in the air — keeps the feet planted (bottom anchor)
                .scaleEffect(x: hop ? 1.0 : 1.07, y: hop ? 1.07 : 0.95, anchor: .bottom)
                .offset(y: hop ? -size * 0.28 : 0)
                .rotationEffect(.degrees(hop ? -7 : 5))
            if showShadow {
                Ellipse()
                    .fill(tint.opacity(0.16))
                    .frame(width: size * (hop ? 0.30 : 0.52), height: size * 0.11)
                    .blur(radius: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: hop)
        .onAppear { hop = true }
    }
}
