import SwiftUI
import AppKit

/// Transparent overlay that turns scroll-wheel / two-finger scroll into discrete steps
/// (one per notch) while letting clicks fall straight through to the board underneath.
struct ScrollNavCatcher: NSViewRepresentable {
    /// +1 = scroll up, -1 = scroll down.
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView(); v.onStep = onStep; return v
    }
    func updateNSView(_ nsView: CatcherView, context: Context) { nsView.onStep = onStep }

    final class CatcherView: NSView {
        var onStep: ((Int) -> Void)?
        private var accum: CGFloat = 0
        private let threshold: CGFloat = 4   // trackpad only

        override func scrollWheel(with event: NSEvent) {
            if event.hasPreciseScrollingDeltas {
                // Trackpad: accumulate a little so a gentle swipe = one move.
                accum += event.scrollingDeltaY
                if accum >= threshold { onStep?(1); accum = 0 }
                else if accum <= -threshold { onStep?(-1); accum = 0 }
            } else {
                // Mouse wheel: one notch = one move, regardless of the OS line-scroll amount.
                let dy = event.scrollingDeltaY
                if dy > 0 { onStep?(1) }
                else if dy < 0 { onStep?(-1) }
            }
        }

        // Only claim scroll events; clicks (mouseDown) pass through to the board below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .scrollWheel: return bounds.contains(point) ? self : nil
            default: return nil
            }
        }
    }
}
