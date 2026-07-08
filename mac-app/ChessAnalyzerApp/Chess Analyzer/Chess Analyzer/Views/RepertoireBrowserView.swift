import SwiftUI

struct RepertoireBrowserView: View {
    @EnvironmentObject var repertoireDB: RepertoireDatabase

    @State private var searchText = ""
    @State private var showingNewRepertoireSheet = false
    @State private var renamingRepertoire: Repertoire?
    @State private var newName = ""
    @State private var repertoireToDelete: Repertoire?
    @State private var showingDeleteAlert = false
    @State private var openRepertoire: Repertoire?

    var body: some View {
        Group {
            if let rep = openRepertoire {
                RepertoireEditorView(repertoire: rep, onClose: { openRepertoire = nil })
            } else {
                libraryBody
            }
        }
    }

    private var libraryBody: some View {
        VStack(spacing: 0) {
            if repertoireDB.repertoireCount == 0 {
                emptyState
            } else {
                header
                grid
            }

            statusBar
        }
        .sheet(isPresented: $showingNewRepertoireSheet) {
            NewRepertoireSheet { name, side, summary in
                showingNewRepertoireSheet = false
                _ = repertoireDB.createRepertoire(name: name, side: side, summary: summary)
            } onCancel: {
                showingNewRepertoireSheet = false
            }
        }
        .alert("Rename Repertoire", isPresented: Binding(
            get: { renamingRepertoire != nil },
            set: { if !$0 { renamingRepertoire = nil } }
        )) {
            TextField("Repertoire name", text: $newName)
            Button("Cancel", role: .cancel) { renamingRepertoire = nil }
            Button("Rename") {
                if let rep = renamingRepertoire {
                    repertoireDB.renameRepertoire(rep, to: newName)
                }
                renamingRepertoire = nil
            }
        }
        .alert("Delete Repertoire", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let rep = repertoireToDelete {
                    repertoireDB.deleteRepertoire(rep)
                }
                repertoireToDelete = nil
            }
            Button("Cancel", role: .cancel) { repertoireToDelete = nil }
        } message: {
            Text("This will permanently delete this repertoire and all its lines.")
        }
    }

    // MARK: - Header (mirrors DatabaseBrowserView.rootView header)

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 18))
                    .foregroundColor(DS.ink60)
                Text("Repertoires")
                    .font(AnnFont.serif(16, .semibold))
                    .foregroundColor(DS.ink)
            }

            Spacer()

            HStack(spacing: 10) {
                // Search field (same design as DatabaseBrowserView)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(DS.ink25)
                    TextField("Search repertoires...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AnnFont.serif(12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(DS.ink25)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 220, height: 32)
                .background(DS.fieldBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DS.borderStrong, lineWidth: 1)
                )

                Button(action: { showingNewRepertoireSheet = true }) {
                    Text("Create Repertoire")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    // MARK: - Grid (reuses rootDatabaseCard styling)

    private var filtered: [Repertoire] {
        guard !searchText.isEmpty else { return repertoireDB.repertoires }
        return repertoireDB.repertoires.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 400, maximum: 500), spacing: 20)
            ], spacing: 16) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, rep in
                    Button(action: { openRepertoire = rep }) {
                        repertoireCard(rep, accent: cardColor(for: index))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open") { openRepertoire = rep }
                        Divider()
                        Button("Rename...") {
                            newName = rep.name
                            renamingRepertoire = rep
                        }
                        Divider()
                        Button("Delete...", role: .destructive) {
                            repertoireToDelete = rep
                            showingDeleteAlert = true
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .frame(maxHeight: .infinity)
    }

    private func cardColor(for index: Int) -> Color {
        let colors: [Color] = [DS.accentGreen, DS.accentOrange, DS.accentPurple, DS.accentRed, DS.accentTeal, DS.accent]
        return colors[index % colors.count]
    }

    // MARK: - Card (mirrors rootDatabaseCard structure)

    private func repertoireCard(_ rep: Repertoire, accent: Color) -> some View {
        VStack(spacing: 0) {
            // Card Header
            HStack(spacing: 12) {
                Image(systemName: rep.side == .white ? "circle" : "circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(rep.side == .white ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background(rep.side == .white ? Color.white : Color.black,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(accent, lineWidth: 2)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(rep.name)
                        .font(AnnFont.serif(14, .semibold))
                        .foregroundColor(DS.ink)
                        .lineLimit(1)
                    Text("\(rep.side.displayName)\(rep.ecoRangeDisplay.map { " · \($0)" } ?? "")")
                        .font(AnnFont.mono(11))
                        .foregroundColor(DS.ink40)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }

            // Card Body
            VStack(spacing: 12) {
                HStack {
                    Text("Positions")
                        .font(AnnFont.label(12))
                        .tracking(12 * 0.1)
                        .foregroundColor(DS.ink40)
                    Spacer()
                    Text("\(rep.nodeCount)")
                        .font(AnnFont.mono(13, bold: true))
                        .foregroundColor(DS.ink)
                }

                HStack {
                    Text("Your moves")
                        .font(AnnFont.label(12))
                        .tracking(12 * 0.1)
                        .foregroundColor(DS.ink40)
                    Spacer()
                    Text("\(rep.userMoveCount)")
                        .font(AnnFont.mono(13, bold: true))
                        .foregroundColor(DS.ink)
                }

                HStack {
                    Text("Last modified")
                        .font(AnnFont.label(12))
                        .tracking(12 * 0.1)
                        .foregroundColor(DS.ink40)
                    Spacer()
                    Text(relativeTimeString(rep.dateModified))
                        .font(AnnFont.mono(12))
                        .foregroundColor(DS.ink60)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.paperRaised)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.19), radius: 10, x: 0, y: 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.textTertiary)

            VStack(spacing: 8) {
                Text("No Repertoires Yet")
                    .font(AnnFont.serif(20, .semibold))
                    .foregroundColor(DS.textPrimary)

                Text("Create a repertoire to start building your opening preparation, line by line.")
                    .font(AnnFont.serif(13))
                    .foregroundColor(DS.textTertiary)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button(action: { showingNewRepertoireSheet = true }) {
                Text("Create Repertoire")
                    .font(AnnFont.label(13))
                    .tracking(13 * 0.1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(DS.accent)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("\(repertoireDB.repertoireCount) repertoires")
                .font(AnnFont.mono(11))
                .foregroundColor(DS.ink25)

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(height: 28)
        .background(DS.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - New Repertoire Sheet (mirrors NewDatabaseSheet structure)

struct NewRepertoireSheet: View {
    let onCreate: (String, RepertoireSide, String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var side: RepertoireSide = .white
    @State private var summary = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Repertoire")
                    .font(AnnFont.serif(16, .semibold))
                    .foregroundColor(DS.textPrimary)

                Spacer()

                Button(action: { onCancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textTertiary)
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

            // Body
            VStack(alignment: .leading, spacing: 20) {
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(DS.textPrimary)

                    TextField("Najdorf Sicilian", text: $name)
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

                // Side picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Side")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(DS.textPrimary)

                    HStack(spacing: 8) {
                        sideButton(.white)
                        sideButton(.black)
                    }
                }

                // Summary
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary")
                        .font(AnnFont.label(13))
                        .tracking(13 * 0.1)
                        .foregroundColor(DS.textPrimary)

                    TextField("Optional — short description", text: $summary)
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
            }
            .padding(24)

            // Footer
            HStack(spacing: 12) {
                Spacer()
                Button(action: { onCancel() }) {
                    Text("Cancel")
                }
                .buttonStyle(GlassButtonStyle())

                Button(action: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, side, summary.trimmingCharacters(in: .whitespaces))
                }) {
                    Text("Create")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
        }
        .frame(width: 480)
        .background(GlassPanelBackground())
    }

    private func sideButton(_ s: RepertoireSide) -> some View {
        let isSelected = side == s
        return Button(action: { side = s }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(s == .white ? Color.white : Color.black)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(DS.textTertiary, lineWidth: 1))
                Text(s.displayName)
                    .font(AnnFont.serif(13, isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DS.accentLight : DS.bg)
            .cornerRadius(DS.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusSM)
                    .strokeBorder(isSelected ? DS.accent : DS.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
