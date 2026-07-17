import SwiftUI

// MARK: - Animation Extensions

extension Animation {
    static var chessMove: Animation {
        .easeInOut(duration: 0.3)
    }
    
    static var chessPiecePlace: Animation {
        .spring(response: 0.3, dampingFraction: 0.7)
    }
    
    static var boardFlip: Animation {
        .easeInOut(duration: 0.5)
    }
}

// MARK: - Transition Extensions

extension AnyTransition {
    static var pieceFade: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.8))
    }
    
    static var pieceCapture: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.1).combined(with: .opacity),
            removal: .scale(scale: 1.2).combined(with: .opacity)
        )
    }
}

// MARK: - View Modifiers

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
                y: 0
            )
        )
    }
}

extension View {
    func shake(amount: Int) -> some View {
        modifier(ShakeEffect(animatableData: CGFloat(amount)))
    }
}

// MARK: - Highlight Animations

struct PulseEffect: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .opacity(isAnimating ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

extension View {
    func pulse() -> some View {
        modifier(PulseEffect())
    }
}

// MARK: - Glow Effect

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: radius)
            .shadow(color: color, radius: radius)
    }
}

extension View {
    func glow(color: Color = .yellow, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}

// MARK: - Square Highlight

struct SquareHighlight: ViewModifier {
    let isHighlighted: Bool
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(color.opacity(isHighlighted ? 0.4 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isHighlighted)
            )
    }
}

extension View {
    func highlightSquare(_ isHighlighted: Bool, color: Color = .yellow) -> some View {
        modifier(SquareHighlight(isHighlighted: isHighlighted, color: color))
    }
}

// MARK: - Move Trail Effect

struct MoveTrail: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

struct MoveTrailView: View {
    let from: Position
    let to: Position
    let squareSize: CGFloat
    
    @State private var progress: CGFloat = 0
    
    var body: some View {
        let fromPoint = CGPoint(
            x: CGFloat(from.file) * squareSize + squareSize / 2,
            y: CGFloat(7 - from.rank) * squareSize + squareSize / 2
        )
        let toPoint = CGPoint(
            x: CGFloat(to.file) * squareSize + squareSize / 2,
            y: CGFloat(7 - to.rank) * squareSize + squareSize / 2
        )
        
        MoveTrail(from: fromPoint, to: toPoint)
            .trim(from: 0, to: progress)
            .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5)) {
                    progress = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        progress = 0
                    }
                }
            }
    }
}

// MARK: - Check Indicator

struct CheckIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .strokeBorder(Color.red, lineWidth: 3)
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .opacity(isAnimating ? 0.0 : 1.0)
            .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}
