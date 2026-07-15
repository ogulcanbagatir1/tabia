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
    // When the editor is opened via BEGIN DRILL, jump straight into a drill session.
    @State private var drillLaunch = false
    // The repertoire selected in the left shelf — its lines show in the center panel.
    // (Opening the full editor is a separate action, via the center "Edit" button.)
    @State private var selectedRepertoire: Repertoire?
    @State private var showingKnowledge = false

    // Per-repertoire SM-2 knowledge (due/coverage/drilled…) + the 7-day due forecast, computed
    // from the position schedules and cached so cards and the training rail don't re-fetch on render.
    @State private var knowledge: [UUID: RepertoireKnowledge] = [:]
    @State private var forecastBuckets: [Int] = Array(repeating: 0, count: 7)

    var body: some View {
        Group {
            if let rep = openRepertoire {
                RepertoireEditorView(repertoire: rep, onClose: { openRepertoire = nil; drillLaunch = false },
                                     autoStartDrill: drillLaunch)
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
                HStack(spacing: 0) {
                    shelfMain
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    rightRail
                        .frame(width: 400)
                        .overlay(alignment: .leading) { Rectangle().fill(DS.hairline).frame(width: 1) }
                }
                .frame(maxHeight: .infinity)
            }

            statusBar
        }
        .onAppear {
            refreshKnowledge()
            if selectedRepertoire == nil { selectedRepertoire = repertoireDB.repertoires.first }
        }
        .onChange(of: repertoireDB.repertoires.count) { _, _ in
            refreshKnowledge()
            if selectedRepertoire == nil { selectedRepertoire = repertoireDB.repertoires.first }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabiaNewRepertoire)) { _ in
            showingNewRepertoireSheet = true
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
        .sheet(isPresented: $showingKnowledge) {
            if let rep = selectedRepertoire {
                RepertoireStatsView(repertoire: rep, repertoireDB: repertoireDB,
                                    onClose: { showingKnowledge = false },
                                    preloaded: knowledge[rep.id])
            }
        }
    }

    // MARK: - Shelf (R1) — "Your Books" grid + training rail

    private var shelfMain: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                (Text("Your Books ").font(AnnFont.serif(26, .semibold)).foregroundColor(DS.ink)
                 + Text("— \(repertoireWord)").font(AnnFont.voice(22)).foregroundColor(DS.ink40))
                Text(aggregateStatLine).font(AnnFont.mono(10)).tracking(0.3).foregroundColor(DS.ink40)
            }
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 20)

            ScrollView {
                // Explicit leading VStack: a ScrollView with multiple children wraps them in an
                // implicit CENTER-aligned stack, which is what pushed the capped grid to the middle.
                VStack(alignment: .leading, spacing: 0) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                        ForEach(filtered) { rep in
                            Button(action: { openRepertoire = rep }) {
                                bookCard(rep)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename…") { newName = rep.name; renamingRepertoire = rep }
                                Divider()
                                Button("Delete…", role: .destructive) { repertoireToDelete = rep; showingDeleteAlert = true }
                            }
                        }
                    }
                    // Cap the grid so cards stay a readable size on wide screens instead of stretching
                    // to half the window each; anchored to the start (left) of the shelf.
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 32)

                    Text("Coverage is measured against your own online games — not against theory you'll never meet.")
                        .font(AnnFont.voice(13)).foregroundColor(DS.ink40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DS.paper)
    }

    private var repertoireWord: String {
        let n = repertoireDB.repertoireCount
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let numStr = n < words.count ? words[n] : "\(n)"
        return "\(numStr) repertoire\(n == 1 ? "" : "s"), one habit"
    }

    // MARK: - Left column — "Your Books" (R1)

    private var leftBooks: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your Books").font(AnnFont.serif(20, .semibold)).foregroundColor(DS.ink)
                    Spacer()
                    newRepertoireButton
                }
                Text(aggregateStatLine).font(AnnFont.mono(9.5)).foregroundColor(DS.ink40).lineLimit(1)
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(filtered) { rep in
                        Button(action: { selectedRepertoire = rep }) {
                            bookCard(rep, selected: selectedRepertoire?.id == rep.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") { openRepertoire = rep }
                            Divider()
                            Button("Rename…") { newName = rep.name; renamingRepertoire = rep }
                            Divider()
                            Button("Delete…", role: .destructive) { repertoireToDelete = rep; showingDeleteAlert = true }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(DS.paper)
    }

    private var newRepertoireButton: some View {
        Button(action: { showingNewRepertoireSheet = true }) { Text("New") }
            .buttonStyle(GlassPrimaryButtonStyle())
    }

    // MARK: - Center — selected repertoire's lines (read-only preview; "Edit" opens the editor)

    private var centerPanel: some View {
        VStack(spacing: 0) {
            if let rep = selectedRepertoire {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rep.name).font(AnnFont.serif(22, .semibold)).foregroundColor(DS.ink)
                        Text(centerMeta(rep)).font(AnnFont.mono(10.5)).foregroundColor(DS.ink40)
                    }
                    Spacer()
                    if let k = knowledge[rep.id], k.dueNow > 0 { dueChip(k.dueNow) }
                    Button(action: { showingKnowledge = true }) { Text("Knowledge") }
                        .buttonStyle(GlassButtonStyle())
                    Button(action: { openRepertoire = rep }) { Text("Edit") }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.horizontal, 26).padding(.vertical, 18)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.hairline).frame(height: 1) }

                linesTree(rep)
            } else {
                centerEmpty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.paper)
    }

    private func centerMeta(_ rep: Repertoire) -> String {
        let cov = Int((knowledge[rep.id]?.coveragePercent ?? 0).rounded())
        return "\(rep.side.displayName.uppercased()) · \(rep.userMoveCount) YOUR MOVES · \(cov)% COVERAGE"
    }

    private var centerEmpty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light)).foregroundColor(DS.ink25)
            Text("Select a repertoire").font(AnnFont.serif(18, .semibold)).foregroundColor(DS.ink)
            Text("Pick a book on the left to see its lines here.")
                .font(AnnFont.voice(14)).foregroundColor(DS.ink40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func linesTree(_ rep: Repertoire) -> some View {
        let rows = flattenedLines(rep)
        if rows.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Text("No lines yet").font(AnnFont.serif(17, .medium)).foregroundColor(DS.ink)
                Text("Open the editor to build this repertoire, move by move.")
                    .font(AnnFont.voice(13.5)).foregroundColor(DS.ink40).multilineTextAlignment(.center)
                Button(action: { openRepertoire = rep }) { Text("Edit") }
                    .buttonStyle(GlassButtonStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in lineRow(row) }
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lineRow(_ row: LineRow) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(row.node.isUserMove ? DS.redAccent : Color.clear)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(row.node.isUserMove ? DS.redAccent : DS.ink40, lineWidth: 1.5))
            Text(moveLabel(row))
                .font(AnnFont.mono(13.5, bold: true)).foregroundColor(DS.ink).fixedSize()
            if !row.node.annotation.isEmpty {
                Text(row.node.annotation).font(AnnFont.voice(13)).foregroundColor(DS.ink40).lineLimit(1)
            }
            Spacer(minLength: 6)
            if row.node.isUserMove {
                Text(row.node.isPrimary ? "MAIN" : "ALT")
                    .font(AnnFont.label(8.5)).tracking(8.5 * 0.12).foregroundColor(DS.ink40)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.borderStrong, lineWidth: 1))
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, CGFloat(row.depth) * 22 + 4)
        .padding(.trailing, 8)
    }

    private func moveLabel(_ row: LineRow) -> String {
        let san = row.node.san ?? row.node.uciMove ?? "—"
        let isWhite = row.ply % 2 == 1
        let num = (row.ply + 1) / 2
        return isWhite ? "\(num). \(san)" : "\(num)… \(san)"
    }

    private struct LineRow: Identifiable {
        let id: UUID
        let node: RepertoireNode
        let depth: Int
        let ply: Int
    }

    private func flattenedLines(_ rep: Repertoire) -> [LineRow] {
        guard let root = rep.nodes.first(where: { $0.id == rep.rootNodeId })
                ?? rep.nodes.first(where: { $0.parent == nil }) else { return [] }
        var rows: [LineRow] = []
        func walk(_ node: RepertoireNode, depth: Int, ply: Int) {
            let kids = node.children.sorted { a, b in
                if a.isPrimary != b.isPrimary { return a.isPrimary }
                return (a.san ?? "") < (b.san ?? "")
            }
            for (i, child) in kids.enumerated() {
                let d = i == 0 ? depth : depth + 1
                rows.append(LineRow(id: child.id, node: child, depth: d, ply: ply + 1))
                walk(child, depth: d, ply: ply + 1)
            }
        }
        walk(root, depth: 0, ply: 0)
        return rows
    }

    private func dueChip(_ n: Int) -> some View {
        Text("\(n) DUE")
            .font(AnnFont.mono(10, bold: true)).foregroundColor(DS.redAccent)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: DS.rBar, style: .continuous).strokeBorder(DS.redAccent, lineWidth: 1))
    }

    // MARK: - Grid (reuses rootDatabaseCard styling)

    private var filtered: [Repertoire] {
        guard !searchText.isEmpty else { return repertoireDB.repertoires }
        return repertoireDB.repertoires.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Right rail — Training Queue + 7-day forecast (R1)

    private var rightRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            trainingQueueCard
            forecastCard
            Text("Twenty cards a day keeps the whole shelf warm. Miss a day and the queue forgives — the intervals just tighten.")
                .font(AnnFont.voice(13)).foregroundColor(DS.ink40).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.paper)
    }

    private var trainingQueueCard: some View {
        let totalDue = knowledge.values.reduce(0) { $0 + $1.dueNow }
        let drilled = knowledge.values.reduce(0) { $0 + $1.drilledDecisions }
        let mature = knowledge.values.reduce(0) { $0 + $1.matureDecisions }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TRAINING QUEUE").font(AnnFont.label(10)).tracking(10 * 0.14).foregroundColor(DS.ink40)
                Spacer()
                Text("SM-2").font(AnnFont.mono(10)).foregroundColor(DS.ink40)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(totalDue)").font(AnnFont.serif(44, .semibold)).foregroundColor(DS.ink)
                Text("CARDS DUE TODAY").font(AnnFont.mono(10.5)).foregroundColor(DS.ink60)
            }
            HStack(spacing: 20) {
                queueStat("\(drilled)", "DRILLED")
                queueStat("\(mature)", "MATURE")
                queueStat("\(averageRetention)%", "RETENTION")
            }
            Button(action: beginDrill) {
                Text("BEGIN DRILL")
                    .font(AnnFont.label(11)).tracking(11 * 0.12).foregroundColor(DS.onRed)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(DS.redAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    private func queueStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(AnnFont.mono(13, bold: true)).foregroundColor(DS.ink)
            Text(label).font(AnnFont.mono(9)).foregroundColor(DS.ink40)
        }
    }

    private var forecastCard: some View {
        let maxCount = max(forecastBuckets.max() ?? 1, 1)
        let labels = forecastDayLabels
        return VStack(alignment: .leading, spacing: 10) {
            Text("NEXT 7 DAYS").font(AnnFont.label(10)).tracking(10 * 0.14).foregroundColor(DS.ink40)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text("\(forecastBuckets[i])").font(AnnFont.mono(8.5)).foregroundColor(DS.ink60)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DS.borderChip)
                            .frame(height: max(CGFloat(forecastBuckets[i]) / CGFloat(maxCount) * 46, 3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    Text(labels[i]).font(AnnFont.mono(8)).foregroundColor(DS.ink25)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: 1) }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    // MARK: - Book card (R1)

    private func bookCard(_ rep: Repertoire, selected: Bool = false) -> some View {
        let k = knowledge[rep.id] ?? .empty
        let cov = Int(k.coveragePercent.rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(rep.name).font(AnnFont.serif(21, .semibold)).foregroundColor(DS.ink).lineLimit(1)
                Spacer(minLength: 6)
                if k.dueNow > 0 { dueChip(k.dueNow) }
            }
            Text(sideLabel(rep))
                .font(AnnFont.label(9)).tracking(9 * 0.12).foregroundColor(DS.ink40).lineLimit(1)
            HStack(spacing: 22) {
                statSpan("\(rep.nodeCount)", "POSITIONS")
                statSpan("\(rep.userMoveCount)", "YOUR MOVES")
            }
            HStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.trackBg)
                        Capsule().fill(DS.semWin)
                            .frame(width: g.size.width * CGFloat(min(max(cov, 0), 100)) / 100)
                    }
                }
                .frame(height: 5)
                Text("\(cov)% COVERED").font(AnnFont.mono(10.5)).foregroundColor(DS.ink60).fixedSize()
            }
            Text(revisedLine(rep.dateModified)).font(AnnFont.mono(9.5)).foregroundColor(DS.ink25)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? DS.selectedMove : DS.paperRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? DS.redAccent : DS.hairline, lineWidth: selected ? 1.5 : 1))
    }

    private func statSpan(_ value: String, _ label: String) -> some View {
        (Text(value + " ").font(AnnFont.mono(11, bold: true))
         + Text(label).font(AnnFont.mono(11))).foregroundColor(DS.ink)
    }

    // MARK: - Derived data

    private func sideLabel(_ rep: Repertoire) -> String {
        var s = rep.side.displayName.uppercased()
        if let eco = rep.ecoRangeDisplay, !eco.isEmpty { s += " · \(eco)" }
        return s
    }

    private func revisedLine(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        let day = 86_400.0
        if secs < day { return "REVISED TODAY" }
        let days = Int(secs / day)
        if days < 7 { return "REVISED \(days)D AGO" }
        let weeks = days / 7
        if weeks < 5 { return "REVISED \(weeks)W AGO" }
        return "REVISED \(days / 30)MO AGO"
    }

    private var aggregateStatLine: String {
        let moves = repertoireDB.repertoires.reduce(0) { $0 + $1.nodeCount }
        let yours = repertoireDB.repertoires.reduce(0) { $0 + $1.userMoveCount }
        let covs = repertoireDB.repertoires.compactMap { knowledge[$0.id]?.coveragePercent }
        let avg = covs.isEmpty ? 0 : Int((covs.reduce(0, +) / Double(covs.count)).rounded())
        return "\(moves) MOVES · \(yours) YOURS · AVG COVERAGE \(avg)%"
    }

    private var averageRetention: Int {
        let vals = knowledge.values.map { $0.knowledgePercent }
        guard !vals.isEmpty else { return 0 }
        return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
    }

    private var forecastDayLabels: [String] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { i in
            fmt.string(from: cal.date(byAdding: .day, value: i, to: today) ?? today).uppercased()
        }
    }

    private func beginDrill() {
        // Open the repertoire with the most cards due and jump straight into the drill session.
        let target = repertoireDB.repertoires.max {
            (knowledge[$0.id]?.dueNow ?? 0) < (knowledge[$1.id]?.dueNow ?? 0)
        }
        drillLaunch = true
        openRepertoire = target ?? repertoireDB.repertoires.first
    }

    private func refreshKnowledge() {
        var map: [UUID: RepertoireKnowledge] = [:]
        var buckets = [Int](repeating: 0, count: 7)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for rep in repertoireDB.repertoires {
            let schedMap = repertoireDB.positionSchedules(for: rep.id)
            map[rep.id] = RepertoireStatsBuilder.build(repertoire: rep, schedules: schedMap.mapValues { $0.stats })
            for sched in schedMap.values {
                guard let due = sched.stats.nextDue else { continue }
                let d = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
                buckets[max(0, min(6, d))] += 1
            }
        }
        knowledge = map
        forecastBuckets = buckets
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
        let moves = repertoireDB.repertoires.reduce(0) { $0 + $1.nodeCount }
        let due = knowledge.values.reduce(0) { $0 + $1.dueNow }
        return HStack {
            Text("\(repertoireDB.repertoireCount) REPERTOIRES · \(moves) MOVES · \(due) DUE")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
            Spacer()
            Text("SPACED REPETITION · SM-2")
                .font(AnnFont.mono(9.5)).foregroundColor(DS.ink40)
        }
        .padding(.horizontal, 18)
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

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header — editorial title + a one-line voice subtitle
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text("New ").font(AnnFont.serif(18, .semibold))
                     + Text("Repertoire").font(AnnFont.voice(18)))
                        .foregroundColor(DS.ink)
                    Text("Name your book and choose the side you'll defend.")
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

            // Body
            VStack(alignment: .leading, spacing: 22) {
                field("Name") {
                    annTextField("Najdorf Sicilian", text: $name)
                }

                field("Side") {
                    HStack(spacing: 10) {
                        sideButton(.white)
                        sideButton(.black)
                    }
                }

                field("Summary  ·  optional") {
                    annTextField("Short description", text: $summary)
                }
            }
            .padding(24)

            // Footer
            HStack(spacing: 10) {
                Spacer()
                Button(action: { onCancel() }) { Text("Cancel") }
                    .buttonStyle(GlassButtonStyle())

                Button(action: {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, side, summary.trimmingCharacters(in: .whitespaces))
                }) {
                    Text("Create Repertoire")
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(!canCreate)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(DS.hairline).frame(height: 1)
            }
        }
        .frame(width: 460)
        .background(DS.paper)
    }

    // Uppercase micro-label above a control — the Annotator field voice.
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(AnnFont.label(10)).tracking(10 * 0.14)
                .foregroundColor(DS.ink40)
            content()
        }
    }

    private func annTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(AnnFont.serif(13.5))
            .foregroundColor(DS.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(DS.fieldBg)
            .cornerRadius(DS.rControl)
            .overlay(
                RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
    }

    private func sideButton(_ s: RepertoireSide) -> some View {
        let isSelected = side == s
        return Button(action: { side = s }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(s == .white ? DS.onRed : DS.ink)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().strokeBorder(DS.ink40, lineWidth: 1))
                Text(s.displayName)
                    .font(AnnFont.label(11)).tracking(11 * 0.08)
                    .foregroundColor(isSelected ? DS.ink : DS.ink40)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DS.redAccent.opacity(0.10) : DS.fieldBg)
            .cornerRadius(DS.rControl)
            .overlay(
                RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                    .strokeBorder(isSelected ? DS.redAccent : DS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
