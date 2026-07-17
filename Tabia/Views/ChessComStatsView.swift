import SwiftUI

struct ChessComStatsView: View {
    @EnvironmentObject var database: GameDatabase
    let username: String
    let selectedTimeClass: String

    private let chessComGreen = DS.ink40

    @State private var stats: ChessComStats?

    var body: some View {
        Group {
            if let stats = stats {
                if stats.totalGames == 0 {
                    emptyState
                } else {
                    statsContent(stats)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Computing stats...")
                        .font(AnnFont.serif(12))
                        .foregroundColor(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadStats() }
        .onChange(of: selectedTimeClass) { _, _ in loadStats() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar")
                .font(.system(size: 36))
                .foregroundColor(DS.textTertiary)
            Text("No games to analyze")
                .font(AnnFont.serif(14, .medium))
                .foregroundColor(DS.textSecondary)
            Text("Import some Chess.com games first")
                .font(AnnFont.serif(12))
                .foregroundColor(DS.textTertiary)
            Spacer()
        }
    }

    private func statsContent(_ stats: ChessComStats) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                ratingChartSection(stats)
                statsBottomRow(stats)
                openingsSection(stats)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Loading

    private func loadStats() {
        stats = database.fetchCachedStats(for: username, timeClass: selectedTimeClass)
    }

    // MARK: - Colors

    static func colorForTimeClass(_ tc: String) -> Color {
        switch tc.lowercased() {
        case "bullet": return DS.ink
        case "blitz":  return DS.ink40
        case "rapid":  return DS.redAccent
        default:       return DS.ink60
        }
    }

    // MARK: - Rating Chart Section

    private func ratingChartSection(_ stats: ChessComStats) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Rating History")
                    .font(AnnFont.serif(14, .semibold))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                // Legend
                HStack(spacing: 16) {
                    legendItem(label: "Bullet", color: DS.ink)
                    legendItem(label: "Blitz", color: DS.ink40)
                    legendItem(label: "Rapid", color: DS.redAccent)
                }
            }

            RatingChartView(
                ratingHistory: stats.ratingHistory,
                selectedTimeClass: selectedTimeClass
            )
            .frame(height: 200)
            .padding(12)
            .background(DS.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DS.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(AnnFont.label(10))
                .tracking(10 * 0.1)
                .foregroundColor(DS.textSecondary)
        }
    }

    // MARK: - Results Breakdown + Performance (Side by Side)

    private func statsBottomRow(_ stats: ChessComStats) -> some View {
        HStack(spacing: 20) {
            resultsBreakdown(stats)
            performanceGrid(stats)
        }
    }

    private func resultsBreakdown(_ stats: ChessComStats) -> some View {
        VStack(spacing: 12) {
            Text("Results Breakdown")
                .font(AnnFont.serif(14, .semibold))
                .foregroundColor(DS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // WDL bar
            wdlBar(wins: stats.wins, draws: stats.draws, losses: stats.losses, total: stats.totalGames)
                .frame(height: 10)

            // Labels
            HStack {
                wdlLabel(dot: DS.wdlWin, text: "Wins", count: stats.wins)
                Spacer()
                wdlLabel(dot: DS.wdlDraw, text: "Draws", count: stats.draws)
                Spacer()
                wdlLabel(dot: DS.wdlLoss, text: "Losses", count: stats.losses)
            }
        }
        .padding(20)
        .background(DS.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        )
    }

    private func wdlBar(wins: Int, draws: Int, losses: Int, total: Int) -> some View {
        GeometryReader { geo in
            let t = CGFloat(max(total, 1))
            let winW = geo.size.width * CGFloat(wins) / t
            let drawW = geo.size.width * CGFloat(draws) / t
            let lossW = geo.size.width * CGFloat(losses) / t

            HStack(spacing: 0) {
                if wins > 0 {
                    Rectangle()
                        .fill(DS.wdlWin)
                        .frame(width: max(winW, 2))
                }
                if draws > 0 {
                    Rectangle()
                        .fill(DS.wdlDraw)
                        .frame(width: max(drawW, 2))
                }
                if losses > 0 {
                    Rectangle()
                        .fill(DS.wdlLoss)
                        .frame(width: max(lossW, 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(DS.wdlFrame, lineWidth: 1))
        }
    }

    private func wdlLabel(dot: Color, text: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
            Text(text)
                .font(AnnFont.label(12))
                .tracking(12 * 0.1)
                .foregroundColor(DS.textSecondary)
            Text(verbatim: "\(count)")
                .font(AnnFont.mono(12, bold: true))
                .foregroundColor(DS.textPrimary)
        }
    }

    private func performanceGrid(_ stats: ChessComStats) -> some View {
        let peakRating = stats.timeControlStats.values.compactMap(\.peakRating).max()

        return VStack(spacing: 12) {
            Text("Performance")
                .font(AnnFont.serif(14, .semibold))
                .foregroundColor(DS.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    perfCell(label: "Win Rate", value: String(format: "%.1f%%", stats.winRate), color: DS.ink)
                    perfCell(label: "Draw Rate", value: String(format: "%.1f%%", stats.totalGames > 0 ? Double(stats.draws) / Double(stats.totalGames) * 100 : 0), color: DS.accent)
                }
                HStack(spacing: 12) {
                    perfCell(label: "Best Win Streak", value: "\(stats.streaks.bestWinStreak)", color: DS.textPrimary)
                    perfCell(label: "Peak Rating", value: peakRating != nil ? "\(peakRating!)" : "-", color: DS.ink)
                }
            }
        }
        .padding(20)
        .background(DS.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DS.borderSubtle, lineWidth: 1)
        )
    }

    private func perfCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AnnFont.label(11))
                .tracking(11 * 0.1)
                .foregroundColor(DS.textTertiary)
            Text(verbatim: value)
                .font(AnnFont.mono(18, bold: true))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Most Played Openings

    private func openingsSection(_ stats: ChessComStats) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Most Played Openings")
                    .font(AnnFont.serif(14, .semibold))
                    .foregroundColor(DS.textPrimary)
                Spacer()
            }

            if stats.openingStats.isEmpty {
                Text("No opening data available")
                    .font(AnnFont.serif(12))
                    .foregroundColor(DS.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    // Table header
                    HStack(spacing: 0) {
                        Text("Opening")
                            .frame(width: 280, alignment: .leading)
                        Text("Games")
                            .frame(width: 80, alignment: .leading)
                        Text("Win / Draw / Loss")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Win Rate")
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(AnnFont.label(11))
                    .tracking(11 * 0.1)
                    .foregroundColor(DS.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(height: 32)
                    .background(DS.bgSecondary)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DS.borderSubtle).frame(height: 1)
                    }

                    // Rows
                    ForEach(Array(stats.openingStats.enumerated()), id: \.element.id) { index, opening in
                        openingRow(opening, isEven: index % 2 == 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(DS.borderSubtle, lineWidth: 1)
                )
            }
        }
    }

    private func openingRow(_ opening: OpeningStats, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            // Opening name
            HStack(spacing: 6) {
                if let eco = opening.eco {
                    Text(eco)
                        .font(AnnFont.mono(9, bold: true))
                        .foregroundColor(chessComGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(chessComGreen.opacity(0.12))
                        .cornerRadius(3)
                }
                Text(opening.name)
                    .font(AnnFont.serif(12))
                    .foregroundColor(DS.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 280, alignment: .leading)

            // Games count
            Text(verbatim: "\(opening.games)")
                .font(AnnFont.mono(12))
                .foregroundColor(DS.textSecondary)
                .frame(width: 80, alignment: .leading)

            // WDL bar
            miniWDLBar(wins: opening.wins, draws: opening.draws, losses: opening.losses, total: opening.games)
                .frame(height: 8)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 16)

            // Win rate
            Text(verbatim: String(format: "%.1f%%", opening.winRate))
                .font(AnnFont.mono(12, bold: true))
                .foregroundColor(opening.winRate >= 50 ? DS.ink : DS.ink40)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(height: 36)
        .background(isEven ? Color.clear : DS.bgSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.borderSubtle).frame(height: 1)
        }
    }

    private func miniWDLBar(wins: Int, draws: Int, losses: Int, total: Int) -> some View {
        GeometryReader { geo in
            let t = CGFloat(max(total, 1))
            HStack(spacing: 1) {
                if wins > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.wdlWin)
                        .frame(width: max(geo.size.width * CGFloat(wins) / t, 2))
                }
                if draws > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.textTertiary)
                        .frame(width: max(geo.size.width * CGFloat(draws) / t, 2))
                }
                if losses > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.wdlLoss)
                        .frame(width: max(geo.size.width * CGFloat(losses) / t, 2))
                }
            }
        }
    }
}

// MARK: - Rating Chart View

private struct RatingChartView: View {
    let ratingHistory: [RatingPoint]
    let selectedTimeClass: String

    private let yAxisWidth: CGFloat = 32
    private let xAxisHeight: CGFloat = 18
    private let gridLineCount = 4

    @State private var hoverLocation: CGPoint? = nil
    @State private var hoveredInfo: HoverInfo? = nil

    private struct HoverInfo {
        let timeClass: String
        let rating: Int
        let date: Date
        let screenPoint: CGPoint
    }

    var body: some View {
        let filtered = selectedTimeClass == "all"
            ? ratingHistory
            : ratingHistory.filter { $0.timeClass == selectedTimeClass }

        if filtered.isEmpty {
            Text("No rating data")
                .font(AnnFont.serif(11))
                .foregroundColor(DS.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let allRatings = filtered.map(\.rating)
            let rawMin = allRatings.min() ?? 0
            let rawMax = allRatings.max() ?? 1500
            let padding = max((rawMax - rawMin) / 6, 25)
            let minRating = rawMin - padding
            let maxRating = rawMax + padding
            let ratingRange = CGFloat(max(maxRating - minRating, 1))
            let minDate = filtered.map(\.date).min() ?? Date()
            let maxDate = filtered.map(\.date).max() ?? Date()
            let dateRange = max(maxDate.timeIntervalSince(minDate), 1)
            let grouped = Dictionary(grouping: filtered, by: \.timeClass)

            HStack(spacing: 0) {
                yAxisLabels(minRating: minRating, maxRating: maxRating)
                    .frame(width: yAxisWidth)

                VStack(spacing: 0) {
                    chartArea(
                        grouped: grouped,
                        minRating: minRating,
                        ratingRange: ratingRange,
                        minDate: minDate,
                        dateRange: dateRange,
                        maxRating: maxRating
                    )

                    xAxisLabels(minDate: minDate, maxDate: maxDate)
                        .frame(height: xAxisHeight)
                }
            }
        }
    }

    private func yAxisLabels(minRating: Int, maxRating: Int) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            ForEach(0..<gridLineCount, id: \.self) { i in
                let frac = CGFloat(i) / CGFloat(gridLineCount - 1)
                let rating = Int(Double(maxRating) - Double(maxRating - minRating) * frac)
                let rounded = (rating / 25) * 25
                Text(verbatim: "\(rounded)")
                    .font(AnnFont.mono(8))
                    .foregroundColor(DS.textTertiary)
                    .position(x: yAxisWidth / 2, y: h * frac)
            }
        }
    }

    private func xAxisLabels(minDate: Date, maxDate: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"

        return GeometryReader { geo in
            let w = geo.size.width
            let inset: CGFloat = 24
            let usable = w - inset * 2
            let labelCount = 5
            ForEach(0..<labelCount, id: \.self) { i in
                let frac = CGFloat(i) / CGFloat(labelCount - 1)
                let date = Date(timeIntervalSince1970: minDate.timeIntervalSince1970 + frac * maxDate.timeIntervalSince(minDate))
                Text(formatter.string(from: date))
                    .font(AnnFont.mono(8))
                    .foregroundColor(DS.textTertiary)
                    .position(x: inset + usable * frac, y: 10)
            }
        }
    }

    private func chartArea(
        grouped: [String: [RatingPoint]],
        minRating: Int, ratingRange: CGFloat,
        minDate: Date, dateRange: TimeInterval,
        maxRating: Int
    ) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                // Grid lines
                ForEach(0..<gridLineCount, id: \.self) { i in
                    let y = h * CGFloat(i) / CGFloat(gridLineCount - 1)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                }

                // Lines per time class
                ForEach(Array(grouped.keys.sorted()), id: \.self) { tc in
                    if let points = grouped[tc], points.count >= 2 {
                        let color = ChessComStatsView.colorForTimeClass(tc)

                        // Gradient fill
                        Path { path in
                            for (i, point) in points.enumerated() {
                                let x = w * CGFloat(point.date.timeIntervalSince(minDate) / dateRange)
                                let y = h - h * CGFloat(point.rating - minRating) / ratingRange
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            let lastX = w * CGFloat(points.last!.date.timeIntervalSince(minDate) / dateRange)
                            let firstX = w * CGFloat(points.first!.date.timeIntervalSince(minDate) / dateRange)
                            path.addLine(to: CGPoint(x: lastX, y: h))
                            path.addLine(to: CGPoint(x: firstX, y: h))
                            path.closeSubpath()
                        }
                        .fill(color.opacity(0.08))

                        // Line
                        Path { path in
                            for (i, point) in points.enumerated() {
                                let x = w * CGFloat(point.date.timeIntervalSince(minDate) / dateRange)
                                let y = h - h * CGFloat(point.rating - minRating) / ratingRange
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(color, lineWidth: 2)

                        // End dot
                        if let last = points.last {
                            let x = w * CGFloat(last.date.timeIntervalSince(minDate) / dateRange)
                            let y = h - h * CGFloat(last.rating - minRating) / ratingRange
                            Circle()
                                .fill(color)
                                .frame(width: 5, height: 5)
                                .position(x: x, y: y)
                        }
                    }
                }

                // Hover crosshair
                if let loc = hoverLocation {
                    Path { path in
                        path.move(to: CGPoint(x: loc.x, y: 0))
                        path.addLine(to: CGPoint(x: loc.x, y: h))
                    }
                    .stroke(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                }

                // Hover dot
                if let info = hoveredInfo {
                    let color = ChessComStatsView.colorForTimeClass(info.timeClass)
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 1))
                        .position(info.screenPoint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMD))
            .overlay(alignment: .topLeading) {
                if let info = hoveredInfo {
                    tooltipView(info: info, chartWidth: w)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    hoveredInfo = findClosestPoint(
                        at: location, width: w, height: h,
                        grouped: grouped, minDate: minDate,
                        dateRange: dateRange, minRating: minRating,
                        ratingRange: ratingRange
                    )
                case .ended:
                    hoverLocation = nil
                    hoveredInfo = nil
                }
            }
        }
    }

    private func findClosestPoint(
        at location: CGPoint, width: CGFloat, height: CGFloat,
        grouped: [String: [RatingPoint]],
        minDate: Date, dateRange: TimeInterval,
        minRating: Int, ratingRange: CGFloat
    ) -> HoverInfo? {
        var bestDist = CGFloat.infinity
        var bestInfo: HoverInfo?

        for (tc, points) in grouped {
            guard selectedTimeClass == "all" || tc == selectedTimeClass else { continue }
            for point in points {
                let x = width * CGFloat(point.date.timeIntervalSince(minDate) / dateRange)
                let y = height - height * CGFloat(point.rating - minRating) / ratingRange
                let dist = abs(x - location.x)
                if dist < bestDist {
                    bestDist = dist
                    bestInfo = HoverInfo(
                        timeClass: tc, rating: point.rating,
                        date: point.date, screenPoint: CGPoint(x: x, y: y)
                    )
                }
            }
        }
        return bestInfo
    }

    private func tooltipView(info: HoverInfo, chartWidth: CGFloat) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        let tooltipWidth: CGFloat = 120
        let xOffset = min(max(info.screenPoint.x - tooltipWidth / 2, 0), chartWidth - tooltipWidth)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(ChessComStatsView.colorForTimeClass(info.timeClass))
                    .frame(width: 6, height: 6)
                Text(info.timeClass.capitalized)
                    .font(AnnFont.label(9))
                    .tracking(9 * 0.1)
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)
            }
            Text(verbatim: "\(info.rating)")
                .font(AnnFont.mono(14, bold: true))
                .foregroundColor(DS.textPrimary)
            Text(formatter.string(from: info.date))
                .font(AnnFont.mono(9))
                .foregroundColor(DS.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.paperRaised)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        )
        .offset(x: xOffset, y: 6)
        .allowsHitTesting(false)
    }
}

#Preview {
    ChessComStatsView(username: "test", selectedTimeClass: "all")
        .environmentObject(GameDatabase.preview())
}
