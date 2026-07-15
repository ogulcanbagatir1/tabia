import SwiftUI
import SwiftData

// MARK: - App Error Reporter
// A single place for surfacing background failures (data saves, syncs) that were previously
// swallowed by `try?`. Instead of silently losing a save, we log it and show a dismissible
// banner so the user knows something went wrong rather than discovering it as missing data.

@MainActor
final class AppErrorReporter: ObservableObject {
    static let shared = AppErrorReporter()
    private init() {}

    /// The message currently shown in the banner, or nil when nothing is pending.
    @Published var message: String?

    private var clearWork: DispatchWorkItem?

    /// Report a failure. Safe to call from any thread — it hops to the main actor internally.
    nonisolated static func report(_ message: String, error: Error? = nil) {
        if let error {
            NSLog("Tabia: %@ — %@", message, String(describing: error))
        } else {
            NSLog("Tabia: %@", message)
        }
        Task { @MainActor in shared.show(message) }
    }

    private func show(_ msg: String) {
        withAnimation(.easeOut(duration: 0.2)) { message = msg }
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.message = nil }
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: work)
    }

    func dismiss() {
        clearWork?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { message = nil }
    }
}

// MARK: - Save helper

extension ModelContext {
    /// Save, and surface any failure to the user instead of dropping it on the floor.
    /// `what` completes the sentence "Couldn't save <what>."
    func saveOrReport(_ what: String = "your changes") {
        do {
            try save()
        } catch {
            AppErrorReporter.report("Couldn't save \(what). Your latest change may not be stored.", error: error)
        }
    }
}

// MARK: - Banner UI

struct ErrorBannerHost: ViewModifier {
    @ObservedObject private var reporter = AppErrorReporter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let msg = reporter.message {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: 0xC8462F))
                    Text(msg)
                        .font(AnnFont.label(12))
                        .foregroundColor(DS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(action: { reporter.dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.ink60)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 520)
                .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    /// Attaches the app-wide error banner (bottom-centered, auto-dismissing).
    func errorBannerHost() -> some View { modifier(ErrorBannerHost()) }
}
