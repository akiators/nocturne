import SwiftUI

/// Расширенная статистика: время за 14 дней (бары), топы треков и исполнителей.
struct StatsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var snapshot: StatsService.Snapshot?
    @State private var period: StatsService.Period = .month

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                periodPicker
                if let snapshot {
                    totalTime(snapshot)
                    dailyChart(snapshot)
                    topArtists(snapshot)
                    topTracks(snapshot)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: period) { _ in reload() }
    }

    private var periodPicker: some View {
        HStack(spacing: 8) {
            ForEach([StatsService.Period.week, .month, .all], id: \.title) { item in
                Button {
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.15)) { period = item }
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(period == item ? Palette.background : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(period == item
                                                   ? AnyShapeStyle(Palette.accent)
                                                   : AnyShapeStyle(Palette.surface)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.hPadding)
    }

    private func totalTime(_ snapshot: StatsService.Snapshot) -> some View {
        HStack(spacing: 14) {
            statCard(icon: "headphones", value: snapshot.totalSeconds.humanDuration, label: "услышано")
            statCard(icon: "play.circle", value: "\(snapshot.playCount)", label: "запусков")
        }
        .padding(.horizontal, Metrics.hPadding)
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title(18))
                    .foregroundColor(Palette.textPrimary)
                Text(label)
                    .font(.caption())
                    .foregroundColor(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }

    private func dailyChart(_ snapshot: StatsService.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Последние 14 дней")
                .font(.title(16))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, Metrics.hPadding)
            let maxSeconds = max(snapshot.perDay.map(\.1).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(snapshot.perDay, id: \.0) { day, seconds in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(seconds > 0 ? AnyShapeStyle(Palette.waveGradient) : AnyShapeStyle(Palette.surface))
                            .frame(height: max(4, CGFloat(seconds / maxSeconds) * 110))
                        Text(Self.dayLabel(day))
                            .font(.system(size: 9))
                            .foregroundColor(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130)
            .padding(.horizontal, Metrics.hPadding)
        }
    }

    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func topArtists(_ snapshot: StatsService.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Топ исполнителей")
                .font(.title(16))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, Metrics.hPadding)
            if snapshot.topArtists.isEmpty {
                Text("За этот период пока нет треков.")
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, Metrics.hPadding)
            }
            ForEach(Array(snapshot.topArtists.enumerated()), id: \.offset) { index, pair in
                HStack {
                    Text("\(index + 1)")
                        .font(.numeric())
                        .foregroundColor(Palette.accent)
                        .frame(width: 26, alignment: .leading)
                    Text(pair.0)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Text("\(pair.1)")
                        .font(.numeric())
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, Metrics.hPadding)
            }
        }
    }

    private func topTracks(_ snapshot: StatsService.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Топ треков")
                .font(.title(16))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, Metrics.hPadding)
                .padding(.bottom, 6)
            ForEach(snapshot.topTracks, id: \.0.id) { track, count in
                TrackRow(track: track, subtitle: "\(count) прослушиваний")
            }
        }
    }

    private func reload() {
        snapshot = environment.stats.snapshot(period: period)
    }
}
