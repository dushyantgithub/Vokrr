import SwiftUI

struct HealthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Health")
                        .font(VokrrTheme.jost(30))
                        .tracking(1)
                    Spacer()
                    Button {
                        Task { await appState.refreshHealthDashboard(force: true) }
                    } label: {
                        HStack(spacing: 7) {
                            if appState.isRefreshingHealth {
                                ProgressView().controlSize(.mini).tint(VokrrTheme.emerald)
                            }
                            Text(dateLabel)
                                .font(VokrrTheme.mono(8))
                                .tracking(2)
                                .foregroundStyle(VokrrTheme.tertiaryText)
                        }
                    }
                    .buttonStyle(VokrrPressStyle())
                    .accessibilityLabel("Refresh Ultrahuman health data")
                }

                if let current = appState.healthDashboard?.current {
                    RecoveryRing(
                        score: Int(current.recovery.score?.value.rounded() ?? 0),
                        label: recoveryLabel(current.recovery.score?.value)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    vitals(current)
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        SleepIndexCard(sleep: current.sleep)
                        MetabolicCard(summary: current)
                        MovementCard(summary: current)
                    }
                    .padding(.top, 16)
                } else {
                    unavailableState
                        .padding(.top, 90)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 130)
        }
        .background(VokrrTheme.background)
        .task {
            await appState.refreshHealthDashboard()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled {
                    await appState.refreshHealthDashboard()
                }
            }
        }
    }

    private func vitals(_ summary: DailyHealthSummary) -> some View {
        let values: [(String, HealthMetricValue?)] = [
            ("HR", summary.latestHeartRate ?? summary.restingHeartRate),
            ("HRV", summary.averageHRV),
            ("SPO2", summary.spo2),
            ("TEMP", summary.skinTemperature),
            ("GLUCOSE", summary.latestGlucose),
            ("VO2 MAX", summary.vo2Max),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.0)
                            .font(VokrrTheme.mono(7))
                            .tracking(1.5)
                            .foregroundStyle(VokrrTheme.tertiaryText)
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(item.1?.formatted() ?? "—")
                                .font(VokrrTheme.jost(17))
                            if let unit = compactUnit(item.1?.unit) {
                                Text(unit)
                                    .font(VokrrTheme.mono(8))
                                    .foregroundStyle(VokrrTheme.secondaryText)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(VokrrTheme.champagne.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(VokrrTheme.champagne.opacity(0.12)))
                }
            }
            .padding(.bottom, 4)
        }
        .scrollClipDisabled()
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(VokrrTheme.emerald)
            Text("ULTRAHUMAN RING")
                .font(VokrrTheme.mono(9, medium: true))
                .tracking(3)
            Text(appState.healthDashboard?.sync.message ?? "Health data will appear after the Ring AIR synchronizes with the Vokrr Hub.")
                .font(VokrrTheme.jost(14))
                .foregroundStyle(VokrrTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateLabel: String {
        if let raw = appState.healthDashboard?.current?.localDate {
            let components = raw.split(separator: "-")
            if components.count == 3,
               let month = Int(components[1]),
               let day = Int(components[2]),
               (1 ... 12).contains(month) {
                let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
                return "\(months[month - 1]) \(day)"
            }
        }
        return Date().formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    private func compactUnit(_ unit: String?) -> String? {
        guard let unit, !unit.isEmpty else { return nil }
        return switch unit.lowercased() {
        case "bpm": "BPM"
        case "ms": "MS"
        case "mg/dl": "MG/DL"
        case "ml/kg/min": nil
        default: unit.uppercased()
        }
    }

    private func recoveryLabel(_ score: Double?) -> String {
        guard let score else { return "SYNCING" }
        if score >= 80 { return "OPTIMAL" }
        if score >= 60 { return "GOOD" }
        return "REST"
    }
}

private struct RecoveryRing: View {
    let score: Int
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(VokrrTheme.champagne.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    VokrrTheme.emerald,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: VokrrTheme.emerald.opacity(0.50), radius: 8)
            Circle()
                .stroke(VokrrTheme.emerald.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(22)
                .rotationEffect(.degrees(spinning ? 360 : 0))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(VokrrTheme.jost(52))
                Text("RECOVERY")
                    .font(VokrrTheme.mono(7.5))
                    .tracking(3)
                    .foregroundStyle(VokrrTheme.emerald)
                Text(label)
                    .font(VokrrTheme.mono(7))
                    .tracking(1.5)
                    .foregroundStyle(VokrrTheme.tertiaryText)
            }
        }
        .frame(width: 190, height: 190)
        .onAppear {
            let target = min(max(CGFloat(score) / 100, 0), 1)
            if reduceMotion {
                progress = target
            } else {
                withAnimation(.timingCurve(0.22, 0.9, 0.32, 1, duration: 1.6)) { progress = target }
                withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { spinning = true }
            }
        }
        .onChange(of: score) { _, newValue in
            let target = min(max(CGFloat(newValue) / 100, 0), 1)
            withAnimation(reduceMotion ? nil : .timingCurve(0.22, 0.9, 0.32, 1, duration: 1.6)) {
                progress = target
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery \(score), \(label.lowercased())")
    }
}

private struct SleepIndexCard: View {
    let sleep: HealthSleepSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private let stageColors: [String: Color] = [
        "rem": VokrrTheme.sleepBlue,
        "deep": VokrrTheme.champagne,
        "light": VokrrTheme.sleepBlue.opacity(0.35),
        "awake": VokrrTheme.champagne.opacity(0.18),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("SLEEP INDEX")
                    .font(VokrrTheme.mono(9))
                    .tracking(2.5)
                    .foregroundStyle(VokrrTheme.sleepBlue)
                Spacer()
                Text(sleep.score.map { String(Int($0.value.rounded())) } ?? "—")
                    .font(VokrrTheme.jost(24))
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(displayStages.enumerated()), id: \.offset) { index, stage in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stageColors[stage.stage] ?? VokrrTheme.secondaryText)
                            .frame(width: max(2, (proxy.size.width - 6) * stage.percentage / 100))
                            .scaleEffect(x: revealed ? 1 : 0, anchor: .leading)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 1 + Double(index) * 0.17),
                                value: revealed
                            )
                    }
                }
            }
            .frame(height: 8)
            .padding(.top, 14)

            HStack(spacing: 14) {
                ForEach(displayStages) { stage in
                    Text("\(stage.stage.uppercased()) \(stage.seconds.healthDuration)")
                        .font(VokrrTheme.mono(7))
                        .tracking(0.7)
                        .foregroundStyle(stageColors[stage.stage] ?? VokrrTheme.tertiaryText)
                }
                if let total = sleep.totalSleepSeconds {
                    Text("\(total.healthDuration) TOTAL")
                        .font(VokrrTheme.mono(7))
                        .tracking(0.7)
                        .foregroundStyle(VokrrTheme.tertiaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard(cornerRadius: 26)
        .onAppear { revealed = true }
    }

    private var displayStages: [HealthSleepStage] {
        let order = ["rem", "deep", "light", "awake"]
        return order.compactMap { name in sleep.stages.first(where: { $0.stage == name }) }
    }
}

private struct MetabolicCard: View {
    let summary: DailyHealthSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("METABOLIC SCORE")
                    .font(VokrrTheme.mono(9))
                    .tracking(2.5)
                    .foregroundStyle(VokrrTheme.champagne)
                Spacer()
                Text(metabolicScore)
                    .font(VokrrTheme.jost(24))
            }
            ZStack {
                Rectangle()
                    .fill(VokrrTheme.emerald.opacity(0.06))
                    .frame(height: 24)
                Sparkline(samples: summary.series["glucose"] ?? [])
                    .trim(from: 0, to: revealed ? 1 : 0)
                    .stroke(VokrrTheme.champagne, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 64)
            .padding(.top, 10)

            HStack(spacing: 14) {
                Text("\(summary.latestGlucose?.formatted() ?? "—") MG/DL NOW")
                    .foregroundStyle(VokrrTheme.primaryText)
                Text("LIVE FROM RING")
                    .foregroundStyle(VokrrTheme.emerald)
                Text("VALIDATED")
                    .foregroundStyle(VokrrTheme.tertiaryText)
            }
            .font(VokrrTheme.mono(7))
            .tracking(0.7)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard(cornerRadius: 26)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2)) { revealed = true }
        }
    }

    private var metabolicScore: String {
        guard let glucose = summary.latestGlucose?.value else { return "—" }
        let distance = abs(glucose - 95)
        return "\(Int(max(0, 100 - distance * 1.6).rounded()))"
    }
}

private struct MovementCard: View {
    let summary: DailyHealthSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("MOVEMENT INDEX")
                    .font(VokrrTheme.mono(9))
                    .tracking(2.5)
                    .foregroundStyle(VokrrTheme.emeraldLight)
                Spacer()
                Text(summary.activity.movementIndex.map { String(Int($0.value.rounded())) } ?? "—")
                    .font(VokrrTheme.jost(24))
            }
            Sparkline(samples: summary.series["motion"] ?? [])
                .trim(from: 0, to: revealed ? 1 : 0)
                .stroke(VokrrTheme.emeraldLight, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(height: 54)
                .padding(.top, 10)

            HStack(spacing: 14) {
                Text("\(summary.activity.steps?.formatted(maximumFractionDigits: 0) ?? "—") STEPS")
                    .foregroundStyle(VokrrTheme.primaryText)
                Text("\(summary.activity.activeMinutes?.formatted(maximumFractionDigits: 0) ?? "—") ACTIVE MIN")
                    .foregroundStyle(VokrrTheme.emerald)
                Text("VO2 MAX \(summary.vo2Max?.formatted() ?? "—")")
                    .foregroundStyle(VokrrTheme.tertiaryText)
            }
            .font(VokrrTheme.mono(7))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard(cornerRadius: 26)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.4)) { revealed = true }
        }
    }
}

private struct Sparkline: Shape {
    let samples: [HealthSample]

    func path(in rect: CGRect) -> Path {
        guard samples.count > 1,
              let minimum = samples.map(\.value).min(),
              let maximum = samples.map(\.value).max() else { return Path() }
        let range = max(maximum - minimum, 1)
        var path = Path()
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + CGFloat(index) / CGFloat(samples.count - 1) * rect.width
            let normalized = (sample.value - minimum) / range
            let y = rect.maxY - CGFloat(normalized) * (rect.height - 10) - 5
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
