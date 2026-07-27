import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// RedesignHome.swift — NOOP reboot, the from-scratch design language.
//
// First-principles premium health UI: no circular rings anywhere; smooth gradient area charts (Oura-style);
// strong type hierarchy (big display numbers, tiny uppercase micro-labels); ONE accent per metric reused
// everywhere; generous negative space. The Home ("Today") shows only today's synthesis — a Morning Briefing,
// a Coach entry, and the key metrics for right now — each tappable into an ISOLATED single-metric detail
// (that screen shows ONLY that metric: value, 7/30/90 trend, vs baseline, its own context — nothing mixed in).
// Computes from `repo` + the pure engines; design-system tokens only; iPhone-first, compiles for macOS too.

// MARK: - Per-metric accent (one colour per metric type, everywhere)

enum MetricAccent {
    static let recovery = StrandPalette.chargeColor      // green
    static let hrv      = StrandPalette.metricPurple     // purple
    static let restingHr = StrandPalette.metricRose      // red
    static let sleep    = StrandPalette.restColor        // blue
    static let effort   = StrandPalette.effortColor      // amber
    static let steps    = StrandPalette.metricCyan       // cyan
}

// MARK: - Gradient area chart (the signature viz — no rings)

struct AreaChart: View {
    let values: [Double]
    let color: Color
    var lineWidth: CGFloat = 2.6
    var showDot: Bool = true
    var pad: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            var lo = values.min() ?? 0
            var hi = values.max() ?? 1
            let r = Swift.max(hi - lo, 1)
            lo -= r * 0.25; hi += r * 0.25
            let span = Swift.max(hi - lo, 0.0001)
            func px(_ i: Int) -> CGFloat { pad + CGFloat(i) / CGFloat(values.count - 1) * (size.width - 2 * pad) }
            func py(_ v: Double) -> CGFloat { size.height - pad - CGFloat((v - lo) / span) * (size.height - 2 * pad) }
            let pts = values.indices.map { CGPoint(x: px($0), y: py(values[$0])) }
            let line = Self.smoothPath(pts)

            var fill = line
            fill.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
            fill.addLine(to: CGPoint(x: pts[0].x, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.42), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if showDot, let last = pts.last {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)),
                         with: .color(color))
                ctx.stroke(Path(ellipseIn: CGRect(x: last.x - 8.5, y: last.y - 8.5, width: 17, height: 17)),
                           with: .color(color.opacity(0.32)), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }

    /// Catmull-Rom → Bézier smoothing for a natural, monotone-ish curve.
    static func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[0]
            let p1 = pts[i], p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Metric spec (the data for a row + its isolated detail)

struct MetricSpec: Identifiable, Equatable {
    let id: String
    let title: String
    let accent: Color
    let valueText: String
    let unit: String
    let series: [Double]          // oldest → newest, up to 90 days
    let statusText: String
    let baselineText: String
    let context: [(String, String, String)]   // (label, value, sub-unit)
    let explainerTitle: String
    let explainerBody: String

    static func == (a: MetricSpec, b: MetricSpec) -> Bool { a.id == b.id && a.valueText == b.valueText }
}

// MARK: - Home

struct RedesignHomeView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @State private var openMetric: MetricSpec?

    private var days: [DailyMetric] { repo.days }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text("Morning briefing").strandMicro().padding(.bottom, 12)
                    briefing.font(StrandFont.title2.weight(.semibold)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    coachEntry
                    Text("Right now").strandMicro().padding(.top, 34).padding(.bottom, 2)
                    ForEach(homeMetrics) { spec in
                        MetricRowView(spec: spec) { openMetric = spec }
                    }
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 22).padding(.top, 8)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())

            if let m = openMetric {
                MetricDetailScreen(spec: m, onClose: { openMetric = nil })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.28), value: openMetric)
    }

    // header
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine).font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textTertiary)
                Text("Today").font(StrandFont.rounded(30, weight: .heavy)).foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            NavigationLink { SettingsView() } label: {
                ProfileAvatarView(imageData: profile.avatarImageData, size: 42).frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 26)
    }

    private var dateLine: String {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEd MMMM")
        return f.string(from: Date())
    }

    // briefing prose (coloured key phrases)
    private var briefing: Text {
        let rec = lastValue(\.recovery)
        let hrvNow = lastValue(\.avgHrv)
        let hrvBase = mean(days.compactMap(\.avgHrv).suffix(30))
        let sleepH = lastValue(\.totalSleepMin).map { $0 / 60 }

        func seg(_ s: String, _ c: Color? = nil) -> Text {
            let t = Text(s); return c != nil ? t.foregroundColor(c!) : t.foregroundColor(StrandPalette.textPrimary)
        }
        guard let rec else {
            return seg("Loop is learning your baseline. Wear your strap a few nights — or import your WHOOP history in Settings to light everything up today.", StrandPalette.textSecondary)
        }
        var out = seg("You ")
        if rec >= 67 { out = out + seg("recovered well overnight — recovery is strong at \(Int(rec.rounded()))", MetricAccent.recovery) }
        else if rec >= 34 { out = out + seg("are in a balanced state — recovery is \(Int(rec.rounded()))", MetricAccent.recovery) }
        else { out = out + seg("are run down — recovery is low at \(Int(rec.rounded()))", MetricAccent.recovery) }
        if let h = hrvNow, let b = hrvBase, b > 0 {
            let pct = Int(((h - b) / b * 100).rounded())
            if pct >= 5 { out = out + seg(", and your ") + seg("HRV is above baseline", MetricAccent.hrv) }
            else if pct <= -5 { out = out + seg(", and your ") + seg("HRV is below baseline", MetricAccent.hrv) }
        }
        out = out + seg(". ")
        if let sh = sleepH {
            if sh < 6.5 { out = out + seg("You slept short last night", MetricAccent.sleep) + seg(" — protect tonight with an earlier bedtime.") }
            else { out = out + seg("You got the sleep you needed", MetricAccent.sleep) + seg(" — keep the bedtime steady.") }
        }
        return out
    }

    private var coachEntry: some View {
        NavigationLink { CoachView() } label: {
            HStack(spacing: 13) {
                Circle().fill(RadialGradient(colors: [.white, MetricAccent.hrv, MetricAccent.sleep],
                                             center: .init(x: 0.32, y: 0.3), startRadius: 0, endRadius: 16))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask your Coach").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
                    Text("\"How should I train today?\"").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [MetricAccent.hrv.opacity(0.22), MetricAccent.sleep.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(StrandPalette.surfaceRaised.opacity(0.45)))
            )
            .noopSoftShadow()
        }
        .buttonStyle(.plain)
        .padding(.top, 22)
    }

    // MARK: metric specs

    private var homeMetrics: [MetricSpec] {
        [MetricBuilder.recovery(days), MetricBuilder.sleep(days),
         MetricBuilder.hrv(days), MetricBuilder.restingHr(days)]
    }

    private func lastValue(_ kp: KeyPath<DailyMetric, Double?>) -> Double? {
        days.compactMap { $0[keyPath: kp] }.last
    }
    private func mean(_ xs: ArraySlice<Double>) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }
}

// MARK: - Metric row

struct MetricRowView: View {
    let spec: MetricSpec
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(spec.title.uppercased()).strandMicro()
                    (Text(spec.valueText).font(StrandFont.rounded(34, weight: .heavy)).foregroundColor(spec.accent)
                        + Text(spec.unit.isEmpty ? "" : " \(spec.unit)").font(StrandFont.caption.weight(.bold)).foregroundColor(StrandPalette.textTertiary))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(width: 104, alignment: .leading)
                AreaChart(values: Array(spec.series.suffix(30)), color: spec.accent, lineWidth: 2.2)
                    .frame(height: 50)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Isolated metric detail (ONLY this metric)

struct MetricDetailScreen: View {
    let spec: MetricSpec
    let onClose: () -> Void
    @State private var window = 7

    private var windowed: [Double] { Array(spec.series.suffix(window)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // header: back + home + metric name
                HStack(spacing: 14) {
                    circleButton("chevron.left", action: onClose)
                    circleButton("house.fill", action: onClose)   // Home — returns to Today
                    Circle().fill(spec.accent).frame(width: 11, height: 11).padding(.leading, 2)
                    Text(spec.title.uppercased()).font(StrandFont.headline).tracking(1)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                }
                .padding(.bottom, 14)

                (Text(spec.valueText).font(StrandFont.rounded(60, weight: .heavy)).foregroundColor(spec.accent)
                    + Text(spec.unit.isEmpty ? "" : " \(spec.unit)").font(StrandFont.title2.weight(.bold)).foregroundColor(StrandPalette.textTertiary))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(spec.statusText).font(StrandFont.subhead.weight(.medium))
                    .foregroundStyle(StrandPalette.textSecondary).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)

                // trend card
                VStack(alignment: .leading, spacing: 0) {
                    Picker("", selection: $window) {
                        Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 14)
                    AreaChart(values: windowed.count >= 2 ? windowed : spec.series, color: spec.accent, lineWidth: 2.8)
                        .frame(height: 150)
                    Text(spec.baselineText).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .padding(.top, 12).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(StrandPalette.surfaceRaised))
                .noopSoftShadow()
                .padding(.top, 22)

                // context trio (metric-specific)
                HStack(spacing: 10) {
                    ForEach(spec.context.indices, id: \.self) { i in
                        let c = spec.context[i]
                        VStack(alignment: .leading, spacing: 8) {
                            Text(c.0.uppercased()).strandMicro()
                            (Text(c.1).font(StrandFont.rounded(24, weight: .bold)).foregroundColor(spec.accent)
                                + Text(c.2.isEmpty ? "" : " \(c.2)").font(StrandFont.caption.weight(.bold)).foregroundColor(StrandPalette.textTertiary))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(StrandPalette.surfaceRaised))
                        .noopSoftShadow()
                    }
                }
                .padding(.top, 14)

                // explainer
                VStack(alignment: .leading, spacing: 7) {
                    Text("About this metric").strandMicro().foregroundStyle(spec.accent)
                    Text(spec.explainerTitle).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Text(spec.explainerBody).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(StrandPalette.surfaceRaised)
                    .overlay(alignment: .leading) { Rectangle().fill(spec.accent).frame(width: 3) }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
                .noopSoftShadow()
                .padding(.top, 16)

                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 22).padding(.top, 20)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .tint(spec.accent)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(StrandPalette.surfaceRaised))
                .noopSoftShadow()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric builders (from repo history)

enum MetricBuilder {
    private static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

    static func recovery(_ days: [DailyMetric]) -> MetricSpec {
        let s = days.compactMap { $0.recovery }
        let v = s.last
        let base = mean(Array(s.suffix(30)))
        let week = mean(Array(s.suffix(7)))
        let status: String
        if let v { status = v >= 67 ? String(localized: "Strong — you're primed to train.")
            : v >= 34 ? String(localized: "Balanced — train to how you feel.")
            : String(localized: "Low — prioritise recovery today.") }
        else { status = String(localized: "Calibrating — wear your strap or import history.") }
        return MetricSpec(id: "recovery", title: "Recovery", accent: MetricAccent.recovery,
            valueText: v.map { "\(Int($0.rounded()))" } ?? "—", unit: v != nil ? "of 100" : "",
            series: s,
            statusText: status,
            baselineText: base.map { String(format: String(localized: "30-day baseline %ld. Today reads against it, not a fixed target."), Int($0.rounded())) } ?? String(localized: "Building your baseline."),
            context: [("This week", week.map { "\(Int($0.rounded()))" } ?? "—", ""),
                      ("Range", s.count >= 2 ? "\(Int((s.suffix(30).min() ?? 0).rounded()))–\(Int((s.suffix(30).max() ?? 0).rounded()))" : "—", ""),
                      ("Baseline", base.map { "\(Int($0.rounded()))" } ?? "—", "")],
            explainerTitle: String(localized: "How ready your body is today"),
            explainerBody: String(localized: "A 0–100 read blended from your overnight HRV, resting heart rate and sleep. High means adapted and ready; low means your body is still catching up."))
    }

    static func hrv(_ days: [DailyMetric]) -> MetricSpec {
        let s = days.compactMap { $0.avgHrv }
        let v = s.last
        let base = mean(Array(s.suffix(30)))
        let week = mean(Array(s.suffix(7)))
        let status: String
        if let v, let b = base, b > 0 {
            let pct = Int(((v - b) / b * 100).rounded())
            status = pct >= 5 ? String(localized: "Above your baseline — a strong recovery signal.")
                : pct <= -5 ? String(localized: "Below your baseline — favour lighter activity.")
                : String(localized: "Right around your baseline.")
        } else { status = String(localized: "Building your baseline.") }
        return MetricSpec(id: "hrv", title: "HRV", accent: MetricAccent.hrv,
            valueText: v.map { "\(Int($0.rounded()))" } ?? "—", unit: v != nil ? "ms" : "",
            series: s,
            statusText: status,
            baselineText: base.map { String(format: String(localized: "Your baseline is %ld ms; today is measured against it."), Int($0.rounded())) } ?? String(localized: "Building your baseline."),
            context: [("7-day avg", week.map { "\(Int($0.rounded()))" } ?? "—", "ms"),
                      ("Baseline", base.map { "\(Int($0.rounded()))" } ?? "—", "ms"),
                      ("Peak 90d", s.suffix(90).max().map { "\(Int($0.rounded()))" } ?? "—", "ms")],
            explainerTitle: String(localized: "The beat-to-beat variation in your heart"),
            explainerBody: String(localized: "Higher variability means your nervous system is recovered and adaptable. It rises with good sleep and rest, and dips with stress, illness or hard training."))
    }

    static func restingHr(_ days: [DailyMetric]) -> MetricSpec {
        let s = days.compactMap { $0.restingHr.map(Double.init) }
        let v = s.last
        let base = mean(Array(s.suffix(30)))
        let week = mean(Array(s.suffix(7)))
        let status: String
        if let v, let b = base {
            status = v <= b - 2 ? String(localized: "Low and steady — a good sign.")
                : v >= b + 3 ? String(localized: "Elevated — your body may be under strain.")
                : String(localized: "Right around your baseline.")
        } else { status = String(localized: "Building your baseline.") }
        return MetricSpec(id: "rhr", title: "Resting HR", accent: MetricAccent.restingHr,
            valueText: v.map { "\(Int($0.rounded()))" } ?? "—", unit: v != nil ? "bpm" : "",
            series: s,
            statusText: status,
            baselineText: base.map { String(format: String(localized: "Baseline %ld bpm. Lower than baseline usually means good recovery."), Int($0.rounded())) } ?? String(localized: "Building your baseline."),
            context: [("7-day avg", week.map { "\(Int($0.rounded()))" } ?? "—", "bpm"),
                      ("Baseline", base.map { "\(Int($0.rounded()))" } ?? "—", "bpm"),
                      ("Lowest 90d", s.suffix(90).min().map { "\(Int($0.rounded()))" } ?? "—", "bpm")],
            explainerTitle: String(localized: "Your heart rate at complete rest"),
            explainerBody: String(localized: "A lower resting heart rate generally reflects better cardiovascular fitness and recovery. A sudden rise can be an early sign of stress or illness."))
    }

    static func sleep(_ days: [DailyMetric]) -> MetricSpec {
        let mins = days.compactMap { $0.totalSleepMin }
        let hours = mins.map { $0 / 60 }
        let v = mins.last
        let week = mean(Array(mins.suffix(7)))
        func hm(_ m: Double) -> String { String(format: "%d:%02d", Int(m) / 60, Int(m) % 60) }
        let status = v.map { $0 >= 390 ? String(localized: "You got the sleep you needed.") : String(localized: "Shorter than your body needs.") }
            ?? String(localized: "No sleep recorded yet.")
        return MetricSpec(id: "sleep", title: "Sleep", accent: MetricAccent.sleep,
            valueText: v.map { hm($0) } ?? "—", unit: v != nil ? "asleep" : "",
            series: hours,
            statusText: status,
            baselineText: String(localized: "Consistency matters as much as total — a steady bedtime is the strongest driver of next-day recovery."),
            context: [("7-night avg", week.map { hm($0) } ?? "—", ""),
                      ("Longest", mins.suffix(30).max().map { hm($0) } ?? "—", ""),
                      ("Shortest", mins.suffix(30).min().map { hm($0) } ?? "—", "")],
            explainerTitle: String(localized: "How long you actually slept"),
            explainerBody: String(localized: "Total time asleep across the night. Meeting your need consistently — at a steady bedtime — is the single biggest lever on how recovered you feel tomorrow."))
    }
}

// MARK: - Small shared styling

extension View {
    /// The redesign's uppercase micro-label styling.
    func strandMicro() -> some View {
        self.font(StrandFont.overlineScaled(11)).tracking(1.6)
            .foregroundStyle(StrandPalette.textTertiary)
    }
    /// Depth via soft shadow, not borders (Linear/Arc-inspired).
    func noopSoftShadow() -> some View {
        self.shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)
    }
}
