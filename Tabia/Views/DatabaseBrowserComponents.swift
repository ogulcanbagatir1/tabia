import SwiftUI

// Standalone components extracted from DatabaseBrowserView so that file stays focused on
// the browser itself. Popovers, filter list, slider, and the new-database / index sheets.

// MARK: - Picker Popover Content

/// Self-contained popover with its own state so data loads reliably on appear.

// MARK: - Filter Inline List

struct FilterInlineList: View {
    let database: GameDatabase
    let cachedNameType: String
    let searchQuery: String
    let selectedValue: String
    let onSelect: (String) -> Void

    @State private var items: [String] = []

    private static let allOpeningNames: [String] = {
        var names = Set(ECODatabase.openings.values)
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    private func fetchItems(query: String) -> [String] {
        if cachedNameType == "opening" {
            let cached = database.cachedNames(type: "opening", query: query)
            let q = query.lowercased()
            let ecoNames: [String]
            if q.isEmpty {
                ecoNames = Array(Self.allOpeningNames.prefix(6))
            } else {
                ecoNames = Self.allOpeningNames.filter { $0.lowercased().contains(q) }
            }
            var seen = Set<String>()
            var merged: [String] = []
            for name in (cached + ecoNames) {
                if seen.insert(name).inserted {
                    merged.append(name)
                }
            }
            return Array(merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.prefix(6))
        } else {
            return Array(database.cachedNames(type: cachedNameType, query: query).prefix(6))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items, id: \.self) { name in
                FilterListItem(
                    name: name,
                    isSelected: selectedValue == name,
                    onSelect: { onSelect(name) }
                )
            }
        }
        .onAppear { items = fetchItems(query: "") }
        .onChange(of: searchQuery) { _, newValue in
            items = fetchItems(query: newValue)
        }
    }
}

private struct FilterListItem: View {
    let name: String
    let isSelected: Bool
    let count: Int?
    let onSelect: () -> Void

    @State private var isHovered = false

    init(name: String, isSelected: Bool, count: Int? = nil, onSelect: @escaping () -> Void) {
        self.name = name
        self.isSelected = isSelected
        self.count = count
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Checkbox
                if isSelected {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.rBar)
                            .fill(DS.accent)
                            .frame(width: 13, height: 13)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(DS.paper)
                    }
                } else {
                    RoundedRectangle(cornerRadius: DS.rBar)
                        .strokeBorder(DS.borderStrong, lineWidth: 1)
                        .frame(width: 13, height: 13)
                }

                Text(name)
                    .font(AnnFont.serif(13.5, isSelected ? .medium : .regular))
                    .foregroundColor(DS.ink)
                    .lineLimit(1)

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(AnnFont.mono(11))
                        .foregroundColor(DS.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? DS.bgHover : (isHovered ? DS.bgHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Dual Slider

struct DualSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = bounds.upperBound - bounds.lowerBound
            let loFrac = (range.lowerBound - bounds.lowerBound) / span
            let hiFrac = (range.upperBound - bounds.lowerBound) / span

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.trackBg)
                    .frame(height: 3)

                // Active range fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.accent)
                    .frame(width: max(0, CGFloat(hiFrac - loFrac) * width), height: 3)
                    .offset(x: CGFloat(loFrac) * width)

                // Low thumb
                sliderThumb
                    .offset(x: CGFloat(loFrac) * width - 7.5)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let raw = bounds.lowerBound + Double(v.location.x / width) * span
                        let snapped = (raw / step).rounded() * step
                        let clamped = max(bounds.lowerBound, min(snapped, range.upperBound - step))
                        range = clamped...range.upperBound
                    })

                // High thumb
                sliderThumb
                    .offset(x: CGFloat(hiFrac) * width - 7.5)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let raw = bounds.lowerBound + Double(v.location.x / width) * span
                        let snapped = (raw / step).rounded() * step
                        let clamped = min(bounds.upperBound, max(snapped, range.lowerBound + step))
                        range = range.lowerBound...clamped
                    })
            }
            .frame(height: 20)
        }
    }

    private var sliderThumb: some View {
        Circle()
            .fill(DS.fieldBg)
            .frame(width: 15, height: 15)
            .overlay(Circle().stroke(DS.accent, lineWidth: 1.5))
    }
}

// MARK: - New Database Sheet

struct NewDatabaseSheet: View {
    @EnvironmentObject var referenceDatabase: ReferenceDatabase
    let onCreate: (String, [URL]) -> Void
    let onCancel: () -> Void
    var onDownloadReference: (() -> Void)? = nil

    @State private var name = ""
    @State private var pgnURLs: [URL] = []
    @State private var isDropTargeted = false
    @State private var showingFilePicker = false
    @State private var downloadStarted = false

    /// Show the in-sheet progress panel while a hosted download is active (also when the sheet is
    /// reopened during an in-flight download — `isDownloading` stays true for the whole operation).
    private var showingProgress: Bool { downloadStarted || referenceDatabase.isDownloading }
    private var downloadActive: Bool { referenceDatabase.isDownloading || referenceDatabase.isImporting }
    private var downloadDone: Bool { downloadStarted && !downloadActive && referenceDatabase.gameCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("New ").font(AnnFont.serif(18, .semibold))
                     + Text("Database").font(AnnFont.voice(18)))
                        .foregroundColor(DS.ink)
                    Text("Download the master reference, or start your own from PGN files.")
                        .font(AnnFont.voice(12.5)).foregroundColor(DS.ink40)
                }

                Spacer()

                Button(action: { onCancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.ink40)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            if showingProgress {
                downloadProgressPanel
            } else {
            // Body
            VStack(alignment: .leading, spacing: 20) {
                // Reference database — one-click download of the big master OTB database
                if let onDownloadReference {
                    Button(action: {
                        referenceDatabase.setDisplayName(name)   // name the reference DB from this field
                        downloadStarted = true
                        onDownloadReference()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(DS.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download reference database")
                                    .font(AnnFont.serif(13, .semibold))
                                    .foregroundColor(DS.textPrimary)
                                Text("9.6M master over-the-board games · ~2 GB")
                                    .font(AnnFont.serif(11))
                                    .foregroundColor(DS.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DS.textTertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(DS.accentLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusMD)
                                .strokeBorder(DS.accent.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(DS.radiusMD)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Rectangle().fill(DS.border).frame(height: 1)
                        Text("or create your own")
                            .font(AnnFont.serif(10))
                            .foregroundColor(DS.textTertiary)
                            .fixedSize()
                        Rectangle().fill(DS.border).frame(height: 1)
                    }
                }

                // Name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("DATABASE NAME")
                        .font(AnnFont.label(10)).tracking(10 * 0.14)
                        .foregroundColor(DS.ink40)

                    TextField("My Tournament Games", text: $name)
                        .textFieldStyle(.plain)
                        .font(AnnFont.serif(13))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(DS.bg)
                        .cornerRadius(DS.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSM)
                                .strokeBorder(DS.border, lineWidth: 1)
                        )
                }

                // Import PGN section
                VStack(alignment: .leading, spacing: 8) {
                    Text("IMPORT PGN  ·  OPTIONAL")
                        .font(AnnFont.label(10)).tracking(10 * 0.14)
                        .foregroundColor(DS.ink40)

                    if pgnURLs.isEmpty {
                        // Drop zone
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 24))
                                .foregroundColor(isDropTargeted ? DS.accent : DS.textTertiary)

                            Text("Drop PGN file here or click to browse")
                                .font(AnnFont.serif(12))
                                .foregroundColor(DS.textSecondary)
                                .multilineTextAlignment(.center)

                            Text(".pgn files supported")
                                .font(AnnFont.serif(10))
                                .foregroundColor(DS.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusMD)
                                .fill(isDropTargeted ? DS.accentLight : DS.bg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusMD)
                                .strokeBorder(
                                    isDropTargeted ? DS.accent : DS.border,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { showingFilePicker = true }
                        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                            handleDrop(providers: providers)
                        }
                    } else {
                        // File list
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(pgnURLs, id: \.absoluteString) { url in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 12))
                                        .foregroundColor(DS.accent)
                                    Text(url.lastPathComponent)
                                        .font(AnnFont.serif(12))
                                        .foregroundColor(DS.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        pgnURLs.removeAll(where: { $0 == url })
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(DS.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(DS.accentLight)
                                .cornerRadius(DS.radiusSM)
                            }

                            Button(action: { showingFilePicker = true }) {
                                Label("Add more...", systemImage: "plus")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(DS.accent)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(24)

            Spacer()

            // Footer
            HStack(spacing: 10) {
                Spacer()

                Button(action: { onCancel() }) { Text("Cancel") }
                    .buttonStyle(GlassButtonStyle())

                Button(action: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let finalName = trimmed.isEmpty ? "Untitled" : trimmed
                    onCreate(finalName, pgnURLs)
                }) {
                    Text(pgnURLs.isEmpty ? "Create Database" : "Create & Import")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
            }  // end else (form section)
        }
        .frame(width: 480)
        .background(DS.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rWindow, style: .continuous)
                .strokeBorder(DS.borderStrong, lineWidth: 1)
        )
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls where !pgnURLs.contains(url) {
                    pgnURLs.append(url)
                }
            }
        }
    }

    /// In-sheet feedback for the one-click hosted download: active phase (bar + games count),
    /// a success state, or an error with retry — so the button never just "goes into the void".
    private var downloadProgressPanel: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            if let err = referenceDatabase.downloadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34)).foregroundColor(DS.moveBlunder)
                Text("Download failed")
                    .font(AnnFont.serif(15, .semibold)).foregroundColor(DS.textPrimary)
                Text(err).font(AnnFont.serif(11)).foregroundColor(DS.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360).lineLimit(4)
                HStack(spacing: 10) {
                    Button("Close") { onCancel() }.buttonStyle(.bordered)
                    Button("Retry") { onDownloadReference?() }.buttonStyle(.borderedProminent)
                }.padding(.top, 4)
            } else if downloadDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34)).foregroundColor(DS.accent)
                Text("\(formatted(referenceDatabase.gameCount)) games ready")
                    .font(AnnFont.serif(15, .semibold)).foregroundColor(DS.textPrimary)
                Text("Open the Reference tab and tap “Build opening index” to make positions searchable — you choose scope and depth.")
                    .font(AnnFont.serif(11)).foregroundColor(DS.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                Button("Done") { onCancel() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 4)
            } else {
                KnightLoader(size: 52)
                Text(referenceDatabase.downloadPhase.isEmpty ? "Starting…" : referenceDatabase.downloadPhase)
                    .font(AnnFont.serif(14, .semibold)).foregroundColor(DS.textPrimary)
                    .padding(.top, 4)
                if referenceDatabase.downloadPhase == "Downloading…" {
                    ProgressView(value: referenceDatabase.downloadProgress).frame(maxWidth: 320)
                    Text("\(Int(referenceDatabase.downloadProgress * 100))%  ·  ~2 GB")
                        .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary)
                } else if referenceDatabase.importProgress > 0 {
                    Text("\(formatted(referenceDatabase.importProgress)) games loaded")
                        .font(AnnFont.mono(11)).foregroundColor(DS.textTertiary)
                }
                Text("You can keep using the app — this continues in the background.")
                    .font(AnnFont.serif(10)).foregroundColor(DS.textTertiary)
                HStack(spacing: 10) {
                    Button("Continue in background") { onCancel() }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { referenceDatabase.cancelDownload() } label: {
                        Text(referenceDatabase.isCancellingDownload ? "Cancelling…" : "Cancel Download")
                    }
                    .buttonStyle(.bordered)
                    .disabled(referenceDatabase.isCancellingDownload)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity).frame(height: 300).padding(24)
        // After a clean cancel that loaded no games, return to the create-database options.
        .onChange(of: referenceDatabase.isDownloading) { _, downloading in
            if !downloading && referenceDatabase.downloadError == nil && referenceDatabase.gameCount == 0 {
                downloadStarted = false
            }
        }
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                handled = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    DispatchQueue.main.async {
                        if !pgnURLs.contains(url) {
                            pgnURLs.append(url)
                        }
                    }
                }
            }
        }
        return handled
    }
}

#Preview {
    DatabaseBrowserView(onGameSelected: { _ in }, state: DatabaseBrowserState())
        .environmentObject(GameDatabase.preview())
        .environmentObject(ReferenceDatabase())
        .frame(width: 900, height: 600)
}

// MARK: - Opening Index Progress Sheet

/// Progress while a database's opening index is built. Reuses the reference-DB pipeline per folder.
struct DatabaseIndexProgressSheet: View {
    let folderName: String
    let onDone: () -> Void

    @ObservedObject private var dbIndex = DatabaseIndex.shared

    private var done: Bool { !dbIndex.isIndexing }
    private var fraction: Double {
        dbIndex.indexTotal > 0 ? min(1, Double(dbIndex.indexProgress) / Double(dbIndex.indexTotal)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                (Text("Opening ").font(AnnFont.serif(18, .semibold))
                 + Text("Index").font(AnnFont.voice(18)))
                    .foregroundColor(DS.ink)
                Text(folderName).font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            // Body
            VStack(alignment: .leading, spacing: 14) {
                Text(done
                     ? "This database is now searchable in the Opening Explorer."
                     : "Replaying games and hashing opening positions…")
                    .font(AnnFont.voice(13.5)).foregroundColor(DS.ink60)
                    .fixedSize(horizontal: false, vertical: true)

                // Progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.trackBg)
                        Capsule().fill(DS.redInk)
                            .frame(width: max(4, geo.size.width * (done ? 1 : fraction)))
                    }
                }
                .frame(height: 6)

                Text("\(dbIndex.indexProgress) / \(dbIndex.indexTotal) games")
                    .font(AnnFont.mono(10)).foregroundColor(DS.ink40)
            }
            .padding(24)

            // Footer
            HStack {
                Spacer()
                Button(action: onDone) { Text(done ? "Done" : "Run in Background") }
                    .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .frame(width: 440)
        .background(DS.paper)
    }
}
