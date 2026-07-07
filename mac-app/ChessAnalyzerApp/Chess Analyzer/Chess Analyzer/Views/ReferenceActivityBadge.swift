import SwiftUI

/// Floating status pill for background reference-DB work (hosted download, game load, or index
/// build). Mounted once at the app root so it stays visible on any screen after the user taps
/// "Continue in background". Purely informational — doesn't intercept clicks underneath.
struct ReferenceActivityBadge: View {
    @EnvironmentObject var referenceDatabase: ReferenceDatabase

    private var active: Bool {
        referenceDatabase.isDownloading || referenceDatabase.isImporting || referenceDatabase.isIndexing
    }

    var body: some View {
        ZStack {
            if active {
                let s = status
                HStack(spacing: 10) {
                    KnightLoader(size: 17, showShadow: false)
                        .frame(width: 20, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                        if !s.detail.isEmpty {
                            Text(s.detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DS.textTertiary)
                        }
                    }
                    if let frac = s.fraction {
                        CircularProgress(fraction: frac)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: active)
    }

    /// (title, detail, optional determinate fraction) for the current background operation.
    private var status: (title: String, detail: String, fraction: Double?) {
        let db = referenceDatabase
        if db.isDownloading {
            switch db.downloadPhase {
            case "Downloading…":
                return ("Downloading database", "\(Int(db.downloadProgress * 100))% · ~2 GB", db.downloadProgress)
            case "Loading games…":
                return ("Loading games", "\(fmt(db.importProgress)) loaded", nil)
            case "":
                return ("Preparing…", "", nil)
            default:
                return (db.downloadPhase.replacingOccurrences(of: "…", with: ""), "", nil)
            }
        }
        if db.isImporting { return ("Loading games", "\(fmt(db.importProgress)) loaded", nil) }
        if db.isIndexing { return ("Building opening index", "\(fmt(db.indexProgress)) games", nil) }
        return ("", "", nil)
    }

    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Tiny determinate ring used inside the activity badge.
private struct CircularProgress: View {
    var fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(DS.border, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(DS.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
