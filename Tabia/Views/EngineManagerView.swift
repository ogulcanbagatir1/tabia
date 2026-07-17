import SwiftUI
import AppKit

struct EngineManagerView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var downloadService = EngineDownloadService()
    @State private var showingAddSheet = false
    @State private var engineStatuses: [UUID: Bool] = [:]
    @State private var selectedEngineId: UUID?

    var body: some View {
        Group {
            if settings.engines.isEmpty {
                engineEmptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Engine Manager")
                                .font(AnnFont.serif(24, .semibold))
                                .foregroundColor(DS.ink)
                            Text("\(settings.engines.count) engine\(settings.engines.count == 1 ? "" : "s") configured")
                                .font(AnnFont.serif(13))
                                .foregroundColor(DS.ink40)
                        }

                        // Engine cards grid
                        engineCardsGrid

                        // Per-engine settings — falls back to the default engine when nothing is
                        // explicitly selected, so the panel is always populated.
                        if let engine = settings.engines.first(where: { $0.id == selectedEngineId }) ?? settings.defaultEngine {
                            engineSettingsCard(engine)
                        }
                    }
                    .frame(maxWidth: 880, alignment: .leading)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 44)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            checkAllEngineStatuses()
            if selectedEngineId == nil { selectedEngineId = settings.defaultEngine?.id }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEngineSheet(downloadService: downloadService, onEngineAdded: { config in
                settings.addEngine(config)
                showingAddSheet = false
                checkAllEngineStatuses()
            })
        }
    }

    // MARK: - Empty State

    private var engineEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "cpu")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.ink25)

            Text("No Engines Configured")
                .font(AnnFont.serif(20, .semibold))
                .foregroundColor(DS.ink)

            Text("Add a chess engine to start analyzing positions.\nStockfish is recommended for the best experience.")
                .font(AnnFont.serif(13))
                .foregroundColor(DS.ink40)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 12) {
                Button(action: { showingAddSheet = true }) {
                    Text("Add Engine")
                        .glassButtonPrimary()
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Engine Cards Grid

    private let cardColumns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 16, alignment: .top)]

    private var engineCardsGrid: some View {
        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 16) {
            ForEach(settings.engines) { engine in
                engineCard(engine)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedEngineId = engine.id
                        }
                    }
                    .contextMenu {
                        if !engine.isDefault {
                            Button("Set as Default") {
                                settings.setDefaultEngine(id: engine.id)
                            }
                        }
                        if engine.source != .cloud {
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(engine.path, inFileViewerRootedAtPath: "")
                            }
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            settings.removeEngine(id: engine.id)
                            engineStatuses.removeValue(forKey: engine.id)
                            if selectedEngineId == engine.id {
                                selectedEngineId = nil
                            }
                        }
                    }
            }

            // Add Engine card
            addEngineCard
        }
    }

    private var addEngineCard: some View {
        Button(action: { showingAddSheet = true }) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(DS.ink40)

                Text("Add Engine")
                    .font(AnnFont.label(12))
                    .tracking(12 * 0.1)
                    .foregroundColor(DS.ink40)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.paperRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func engineCard(_ engine: EngineConfig) -> some View {
        let isCloud = engine.source == .cloud
        let isAvailable = isCloud ? true : (engineStatuses[engine.id] ?? false)
        let statusColor: Color = isCloud ? DS.semOnline : (isAvailable ? DS.semOnline : DS.semWarning)
        let iconColor: Color = engine.isDefault ? DS.redAccent : DS.ink60

        return VStack(alignment: .leading, spacing: 14) {
            // Top row: icon + active badge
            HStack {
                Image(systemName: isCloud ? "cloud" : (engine.name.lowercased().contains("leela") || engine.name.lowercased().contains("lc0") ? "brain" : "cpu"))
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(engine.isDefault ? DS.redAccent.opacity(0.125) : DS.fieldBg)
                    )

                Spacer()

                if engine.isDefault {
                    Text("Active")
                        .font(AnnFont.label(10))
                        .tracking(10 * 0.1)
                        .foregroundColor(DS.redAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DS.redAccent.opacity(0.19), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            // Engine info
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.name)
                    .font(AnnFont.serif(15, .semibold))
                    .foregroundColor(DS.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(isCloud ? "Online" : (isAvailable ? "Available" : "Not Found"))
                        .font(AnnFont.label(11))
                        .tracking(11 * 0.1)
                        .foregroundColor(isAvailable || isCloud ? DS.semOnline : DS.ink40)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.paperRaised)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    engine.isDefault ? DS.redAccent : DS.hairline,
                    lineWidth: engine.isDefault ? 2 : 1
                )
        )
        .shadow(
            color: Color.black.opacity(0.19),
            radius: engine.isDefault ? 15 : 10,
            x: 0,
            y: 4
        )
    }

    // MARK: - Per-Engine Settings Card

    private func engineSettingsCard(_ engine: EngineConfig) -> some View {
        let isCloud = engine.source == .cloud

        return VStack(spacing: 0) {
            // Title row
            HStack(spacing: 10) {
                Text("Settings — \(engine.name)")
                    .font(AnnFont.serif(13, .semibold))
                    .foregroundColor(DS.ink)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            if !isCloud {
                // Threads
                settingsRow(
                    label: "Threads",
                    description: "CPU cores for parallel search",
                    showBorder: true
                ) {
                    settingsSlider(
                        label: "",
                        value: engine.settings.threads,
                        range: EngineSettings.threadsRange,
                        onChange: { val in
                            var s = engine.settings
                            s.threads = val
                            settings.updateEngineSettings(id: engine.id, settings: s)
                        }
                    )
                    .frame(width: 160)
                }

                // Hash
                settingsRow(
                    label: "Hash (MB)",
                    description: "Memory for position cache",
                    showBorder: true
                ) {
                    HStack(spacing: 0) {
                        hashSlider(engine)
                    }
                    .frame(width: 160)
                }
            }

            // MultiPV
            settingsRow(
                label: "Analysis Lines",
                description: "Number of variations to calculate",
                showBorder: !isCloud
            ) {
                multiPVStepper(engine)
            }

            if !isCloud {
                // Depth
                settingsRow(
                    label: "Search Depth",
                    description: "Maximum plies to search",
                    showBorder: false
                ) {
                    settingsSlider(
                        label: "",
                        value: engine.settings.depth,
                        range: EngineSettings.depthRange,
                        onChange: { val in
                            var s = engine.settings
                            s.depth = val
                            settings.updateEngineSettings(id: engine.id, settings: s)
                        }
                    )
                    .frame(width: 160)
                }
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.paperRaised)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 6)
        .transition(.opacity)
    }

    private func settingsRow<Control: View>(
        label: String,
        description: String,
        showBorder: Bool,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AnnFont.serif(13, .medium))
                    .foregroundColor(DS.ink)
                Text(description)
                    .font(AnnFont.serif(11))
                    .foregroundColor(DS.ink40)
            }

            Spacer()

            control()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showBorder {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
        }
    }

    // settingsLeftColumn removed — settings split into Performance + Analysis cards

    private func hashSlider(_ engine: EngineConfig) -> some View {
        HStack(spacing: 10) {
            DesignSlider(
                value: log2(Double(engine.settings.hashMB)),
                range: log2(16)...log2(4096),
                step: 1,
                onChange: { val in
                    var s = engine.settings
                    s.hashMB = Int(pow(2.0, val))
                    settings.updateEngineSettings(id: engine.id, settings: s)
                }
            )

            Text("\(engine.settings.hashMB)")
                .font(AnnFont.mono(12, bold: true))
                .foregroundColor(DS.inkData)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // settingsRightColumn removed — settings split into Performance + Analysis cards

    private func multiPVStepper(_ engine: EngineConfig) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                if engine.settings.multiPV > EngineSettings.multiPVRange.lowerBound {
                    var s = engine.settings
                    s.multiPV -= 1
                    settings.updateEngineSettings(id: engine.id, settings: s)
                }
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.ink60)
                    .frame(width: 30, height: 28)
                    .background(DS.fieldBg)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 0, topTrailingRadius: 0))
            }
            .buttonStyle(.plain)

            Text("\(engine.settings.multiPV)")
                .font(AnnFont.mono(13, bold: true))
                .foregroundColor(DS.inkData)
                .frame(width: 36, height: 28)
                .background(DS.fieldBg)
                .overlay(
                    Rectangle().fill(DS.hairline).frame(width: 1), alignment: .leading
                )
                .overlay(
                    Rectangle().fill(DS.hairline).frame(width: 1), alignment: .trailing
                )

            Button(action: {
                if engine.settings.multiPV < EngineSettings.multiPVRange.upperBound {
                    var s = engine.settings
                    s.multiPV += 1
                    settings.updateEngineSettings(id: engine.id, settings: s)
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.ink60)
                    .frame(width: 30, height: 28)
                    .background(DS.fieldBg)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 8, topTrailingRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DS.borderChip, lineWidth: 1)
        )
    }

    private func settingsSlider(label: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 6) {
            if !label.isEmpty {
                HStack {
                    Text(label)
                        .font(AnnFont.serif(12, .medium))
                        .foregroundColor(DS.ink60)
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                DesignSlider(
                    value: Double(value),
                    range: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1,
                    onChange: { onChange(Int($0)) }
                )

                Text("\(value)")
                    .font(AnnFont.mono(12, bold: true))
                    .foregroundColor(DS.inkData)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    // MARK: - Helpers

    private func checkAllEngineStatuses() {
        let fm = FileManager.default
        for engine in settings.engines {
            if engine.source == .cloud {
                engineStatuses[engine.id] = true
            } else {
                let available = fm.fileExists(atPath: engine.path)
                engineStatuses[engine.id] = available
            }
        }
        if selectedEngineId == nil, let defaultEngine = settings.engines.first(where: { $0.isDefault }) {
            selectedEngineId = defaultEngine.id
        }
    }
}

// MARK: - Custom Slider

private struct DesignSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    @State private var isDragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let thumbX = fraction * trackWidth

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.trackBg)
                    .frame(height: 4)

                // Fill track
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.redAccent)
                    .frame(width: max(0, thumbX), height: 4)

                // Knob
                Circle()
                    .fill(DS.paperRaised)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                    .frame(width: 14, height: 14)
                    .offset(x: thumbX - 7)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let frac = max(0, min(1, drag.location.x / trackWidth))
                        let raw = range.lowerBound + frac * (range.upperBound - range.lowerBound)
                        let stepped = step > 0 ? (round(raw / step) * step) : raw
                        let clamped = max(range.lowerBound, min(range.upperBound, stepped))
                        onChange(clamped)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 14)
    }
}

// MARK: - Add Engine Sheet

struct AddEngineSheet: View {
    @ObservedObject var downloadService: EngineDownloadService
    var onEngineAdded: (EngineConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEntryId: String? = "stockfish"
    @State private var downloadedEntries: Set<String> = []
    @State private var downloadingEntryId: String?
    @State private var showingWeightsPicker = false
    @State private var pendingLc0Path: String?
    @State private var localEnginePath: String = ""

    // All selectable entries: registry + cloud
    private struct EngineOption: Identifiable {
        let id: String
        let name: String
        let description: String
        let icon: String
        let iconColor: Color
        let versionLabel: String
        let registryEntry: EngineRegistryEntry?
        let isCloud: Bool
    }

    private var allEngines: [EngineOption] {
        var options: [EngineOption] = EngineRegistryEntry.available.map { entry in
            let version: String
            if let v = downloadService.installedVersion(for: entry) {
                version = "v\(v)"
            } else if entry.id == "stockfish" {
                version = "Latest"
            } else if entry.id == "lc0" {
                version = downloadedEntries.contains(entry.id) ? "Installed" : ""
            } else {
                version = ""
            }
            return EngineOption(
                id: entry.id,
                name: entry.name,
                description: entry.description,
                icon: entry.icon,
                iconColor: entry.color,
                versionLabel: version,
                registryEntry: entry,
                isCloud: false
            )
        }
        options.append(EngineOption(
            id: "cloud",
            name: "Lichess Cloud",
            description: "Free cloud analysis — no download needed",
            icon: "cloud",
            iconColor: .teal,
            versionLabel: "Free",
            registryEntry: nil,
            isCloud: true
        ))
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.system(size: 20))
                        .foregroundColor(DS.redAccent)
                    Text("Add Engine")
                        .font(AnnFont.serif(16, .semibold))
                        .foregroundColor(DS.ink)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.ink40)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            downloadTabContent

            // Status bar
            if downloadService.isDownloading && !downloadService.statusText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(downloadService.statusText)
                        .font(AnnFont.serif(12))
                        .foregroundColor(DS.ink60)
                    Spacer()
                    ProgressView(value: downloadService.progress)
                        .frame(width: 80)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(DS.redAccent.opacity(0.06))
            }

            if let error = downloadService.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(DS.semWarning)
                        .font(.system(size: 12))
                    Text(error)
                        .font(AnnFont.serif(12))
                        .foregroundColor(DS.ink60)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(DS.semWarning.opacity(0.08))
            }

            // "or" divider
            HStack(spacing: 12) {
                Rectangle().fill(DS.hairline).frame(height: 1)
                Text("or")
                    .font(AnnFont.label(11))
                    .tracking(11 * 0.1)
                    .foregroundColor(DS.ink40)
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
            .padding(.horizontal, 24)

            // Local section inline
            localSectionInline

            // Footer
            HStack {
                Spacer()

                Button(action: { dismiss() }) {
                    Text("Cancel")
                }
                .buttonStyle(GlassButtonStyle())

                if !localEnginePath.isEmpty {
                    Button(action: addLocalEngine) { Text("Add Local Engine") }
                        .buttonStyle(GlassButtonStyle())
                }

                Button(action: downloadSelected) {
                    Text("Download & Install")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(selectedEntryId == nil || downloadService.isDownloading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
        }
        .frame(width: 520, height: 580)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.paperRaised)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.37), radius: 20, x: 0, y: 12)
        .onAppear { checkDownloadedEngines() }
        .sheet(isPresented: $showingWeightsPicker) {
            Lc0WeightsSheet(downloadService: downloadService) {
                showingWeightsPicker = false
            }
        }
    }

    // MARK: - Local Section Inline
    private var localSectionInline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a local engine")
                .font(AnnFont.serif(13, .medium))
                .foregroundColor(DS.ink)

            Text("Point to a UCI-compatible engine binary on your machine.")
                .font(AnnFont.serif(11))
                .foregroundColor(DS.ink40)

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ink40)

                    if localEnginePath.isEmpty {
                        Text("/usr/local/bin/stockfish")
                            .font(AnnFont.mono(12))
                            .foregroundColor(DS.ink60)
                    } else {
                        Text(localEnginePath)
                            .font(AnnFont.mono(12))
                            .foregroundColor(DS.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DS.borderStrong, lineWidth: 1)
                )

                Button(action: browseForEngine) {
                    Text("Browse...")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Download Tab

    private var downloadTabContent: some View {
        VStack(spacing: 0) {
            // Engine list
            VStack(spacing: 0) {
                ForEach(allEngines) { engine in
                    engineRow(engine)
                }
            }
            .padding(.vertical, 12)

            Spacer(minLength: 0)
        }
    }

    private func engineRow(_ engine: EngineOption) -> some View {
        let isSelected = selectedEntryId == engine.id
        let isInstalled = downloadedEntries.contains(engine.id) ||
            (engine.isCloud && AppSettings.shared.engines.contains(where: { $0.source == .cloud }))
        let isDownloading = downloadService.isDownloading && downloadingEntryId == engine.id

        return Button(action: { selectedEntryId = engine.id }) {
            HStack(spacing: 14) {
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? DS.redAccent : DS.borderStrong, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(DS.redAccent)
                            .frame(width: 8, height: 8)
                    }
                }

                // Icon
                Image(systemName: engine.icon)
                    .font(.system(size: 18))
                    .foregroundColor(engine.iconColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? DS.selectedWash : engine.iconColor.opacity(0.12))
                    )

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(engine.name)
                            .font(AnnFont.serif(13, .medium))
                            .foregroundColor(DS.ink)

                        if isInstalled {
                            Text("Installed")
                                .font(AnnFont.label(9))
                                .tracking(9 * 0.1)
                                .foregroundColor(DS.semOnline)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(DS.semOnline.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(engine.description)
                        .font(AnnFont.serif(11))
                        .foregroundColor(DS.ink40)
                        .lineLimit(1)
                }

                Spacer()

                // Version / progress
                if isDownloading {
                    ProgressView(value: downloadService.progress)
                        .frame(width: 60)
                } else {
                    Text(engine.versionLabel)
                        .font(AnnFont.mono(11))
                        .foregroundColor(isSelected ? DS.ink60 : DS.ink40)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? DS.selectedWash : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func downloadSelected() {
        guard let entryId = selectedEntryId else { return }

        // Handle cloud engine
        if entryId == "cloud" {
            let config = EngineConfig(
                id: UUID(),
                name: "Lichess Cloud",
                path: "",
                isDefault: false,
                source: .cloud
            )
            onEngineAdded(config)
            dismiss()
            return
        }

        // Handle external link engines
        guard let entry = EngineRegistryEntry.available.first(where: { $0.id == entryId }) else { return }
        if case .externalLink(let url) = entry.downloadType {
            downloadService.openExternalDownload(url: url)
            return
        }

        // Download engine
        downloadingEntryId = entry.id
        Task {
            do {
                let path = try await downloadService.downloadEngine(entry: entry)
                let version = downloadService.installedVersion(for: entry)
                let displayName = version != nil ? "\(entry.name) (\(version!))" : entry.name
                let config = EngineConfig(
                    id: UUID(),
                    name: displayName,
                    path: path,
                    isDefault: AppSettings.shared.engines.isEmpty,
                    source: .downloaded
                )
                await MainActor.run {
                    downloadedEntries.insert(entry.id)
                    downloadingEntryId = nil
                    onEngineAdded(config)

                    if entry.needsWeights {
                        pendingLc0Path = path
                        showingWeightsPicker = true
                    }
                }
            } catch {
                await MainActor.run { downloadingEntryId = nil }
            }
        }
    }

    private func addLocalEngine() {
        guard !localEnginePath.isEmpty else { return }
        let name = URL(fileURLWithPath: localEnginePath).deletingPathExtension().lastPathComponent.capitalized
        let config = EngineConfig(
            id: UUID(),
            name: name,
            path: localEnginePath,
            isDefault: AppSettings.shared.engines.isEmpty,
            source: .custom
        )
        onEngineAdded(config)
        dismiss()
    }

    private func browseForEngine() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a UCI engine executable"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                localEnginePath = url.path
            }
        }
    }

    private func checkDownloadedEngines() {
        for entry in EngineRegistryEntry.available {
            if downloadService.isEngineDownloaded(entry: entry) {
                downloadedEntries.insert(entry.id)
            }
        }
    }
}

// MARK: - Lc0 Weights Sheet

struct Lc0WeightsSheet: View {
    @ObservedObject var downloadService: EngineDownloadService
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var downloadingWeightsId: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download Neural Network")
                        .font(AnnFont.serif(16, .semibold))
                    Text("Lc0 requires a neural network weights file to play")
                        .font(AnnFont.serif(12))
                        .foregroundColor(DS.textSecondary)
                }
                Spacer()
                Button("Skip") { dismiss(); onDone() }
                    .buttonStyle(GlassButtonStyle())
                    .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Lc0WeightsOption.presets) { option in
                        weightsRow(option)
                    }
                }
                .padding(20)
            }

            if downloadService.isDownloading && !downloadService.statusText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(downloadService.statusText)
                        .font(AnnFont.serif(12))
                        .foregroundColor(DS.textSecondary)
                    Spacer()
                    ProgressView(value: downloadService.progress)
                        .frame(width: 80)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(DS.accent.opacity(0.06))
            }
        }
        .frame(width: 460, height: 380)
    }

    private func weightsRow(_ option: Lc0WeightsOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(option.name)
                    .font(AnnFont.serif(13, .semibold))
                Text(option.description)
                    .font(AnnFont.serif(11))
                    .foregroundColor(DS.textSecondary)
            }

            Spacer()

            Text(option.size)
                .font(AnnFont.mono(11))
                .foregroundColor(DS.textSecondary)

            if downloadService.isDownloading && downloadingWeightsId == option.id {
                ProgressView(value: downloadService.progress)
                    .frame(width: 60)
            } else {
                Button("Download") {
                    downloadWeights(option)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .controlSize(.small)
                .disabled(downloadService.isDownloading)
            }
        }
        .padding(12)
        .background(DS.card)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    private func downloadWeights(_ option: Lc0WeightsOption) {
        downloadingWeightsId = option.id
        Task {
            do {
                _ = try await downloadService.downloadWeights(option: option)
                await MainActor.run {
                    downloadingWeightsId = nil
                    dismiss()
                    onDone()
                }
            } catch {
                await MainActor.run { downloadingWeightsId = nil }
            }
        }
    }
}

#Preview {
    EngineManagerView()
        .frame(width: 700, height: 600)
}
