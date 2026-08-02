#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Phase 2 · Coach — the prototype's conversational Coach, native SwiftUI driving the
/// REAL `AICoachEngine` (`model.coach`): the actual chat history (`coach.messages`),
/// live send (`coach.send`), the sending/typing state and error surface. Recovery-based
/// forecast cards come from `repo`. Full provider/key/consent configuration is reached
/// by presenting the existing `CoachView` in a sheet, so nothing about the AI coach is
/// lost or reimplemented — only the chat surface is restyled to the approved design.
struct PremiumCoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    @EnvironmentObject var repo: Repository
    @State private var draft = ""
    @State private var showSettings = false

    private var recovery: Double? {
        for d in repo.days.reversed() { if let v = d.recovery { return v } }
        return repo.today?.recovery
    }

    private let quickPrompts = ["How hard can I go today?", "Should I nap?",
                                "Analyze my HRV", "Plan my week"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        forecastStrip
                        recoveryTrendCard
                        signalsRow
                        if coach.isConfigured {
                            thread
                        } else {
                            setupCard
                        }
                        if let e = coach.errorText, !e.isEmpty {
                            Text(e).font(StrandFont.footnote).foregroundStyle(StrandPalette.statusCritical)
                        }
                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .onChange(of: coach.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            if coach.isConfigured { composer }
        }
        .background(ambient.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            NavigationStack { CoachView() }
        }
    }

    private var ambient: some View {
        ZStack {
            StrandPalette.surfaceBase
            RadialGradient(colors: [StrandPalette.gold.opacity(0.12), .clear],
                           center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 320)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR ON-DEVICE GUIDE").font(StrandFont.overline).tracking(1.4)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Coach").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(StrandPalette.surfaceRaised))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Forecast strip (recovery-derived)

    private var forecastStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                todayForecastCard
                forecastCard("TOMORROW", "Recovery pending", "shield.fill", StrandPalette.sleepDeep)
                forecastCard("THIS WEEK", "Build & balance", "chart.line.uptrend.xyaxis", StrandPalette.gold)
            }
        }
    }
    /// Same card shape as `forecastCard`, but TODAY carries the real, live recovery score as a
    /// glyph-mode `RecoveryRing` (score ring + core dot, no centre number) instead of a flat SF Symbol —
    /// the one forecast that has a real number behind it gets to show it.
    private var todayForecastCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = recovery {
                RecoveryRing(score: r, diameter: 34, lineWidth: 4,
                             showsLabel: false, showsWordmark: false, showsHover: false)
            } else {
                Image(systemName: "flame.fill").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StrandPalette.recoveryColor(80))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(StrandPalette.recoveryColor(80).opacity(0.16)))
            }
            Text("TODAY").font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
            Text(recTitle).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .fill(StrandPalette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }
    private func forecastCard(_ day: String, _ title: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.16)))
            Text(day).font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
            Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .fill(StrandPalette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }
    private var recTitle: String {
        guard let r = recovery else { return "Ease in" }
        return r >= 67 ? "Ready to push" : r >= 34 ? "Train with care" : "Rest & restore"
    }

    /// Real 14-day recovery history so the coach's context has a visible trend, not just a
    /// single-day forecast strip.
    private var recoveryTrendCard: some View {
        let history = repo.days.suffix(14).compactMap { $0.recovery }
        return StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECOVERY · LAST 14 DAYS").font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                if history.count >= 2 {
                    Sparkline(values: history, gradient: StrandPalette.recoveryGradient,
                              lineWidth: 2.5, showsArea: true, showsHead: true, showsHover: true,
                              valueFormat: { "\(Int($0.rounded()))%" })
                        .frame(height: 56)
                } else {
                    Text("Keep logging to see your recovery trend here.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    /// A quick "what the coach can see" glance: real 7-day HRV / resting HR / sleep mini-trends,
    /// so the chat's context is visible before you even ask.
    private var signalsRow: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("THIS WEEK'S SIGNALS").font(StrandFont.overline).tracking(1.2)
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(alignment: .top, spacing: 14) {
                    signalMini("HRV", repo.days.suffix(7).compactMap { $0.avgHrv },
                               StrandPalette.metricCyan, unit: "ms")
                    signalMini("Resting HR", repo.days.suffix(7).compactMap { $0.restingHr.map(Double.init) },
                               StrandPalette.metricRose, unit: "bpm")
                    signalMini("Sleep", repo.days.suffix(7).compactMap { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } },
                               StrandPalette.sleepDeep, unit: "%")
                }
            }
        }
    }
    private func signalMini(_ label: String, _ values: [Double], _ tint: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            if values.count >= 2 {
                Sparkline(values: values, gradient: Gradient(colors: [tint, tint.opacity(0.55)]),
                          lineWidth: 1.8, showsArea: false, showsHead: true, showsHover: false)
                    .frame(height: 28)
            } else {
                Text("—").font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary).frame(height: 28)
            }
            if let last = values.last {
                Text("\(Int(last.rounded())) \(unit)").font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Thread

    private var thread: some View {
        VStack(alignment: .leading, spacing: 12) {
            if coach.messages.isEmpty {
                Text("Ask your coach anything about today's training, recovery or sleep.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .padding(.vertical, 8)
            }
            ForEach(coach.messages) { m in bubble(m) }
            if coach.sending { typingBubble }
            // Quick prompts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { p in
                        Button { send(p) } label: {
                            Text(p).font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(Capsule().fill(StrandPalette.surfaceRaised))
                                .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .user { Spacer(minLength: 44) }
            Text(m.text)
                .font(StrandFont.body)
                .foregroundStyle(m.role == .user ? StrandPalette.goldDeepText : StrandPalette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(bubbleBackground(m.role))
                .fixedSize(horizontal: false, vertical: true)
            if m.role == .assistant { Spacer(minLength: 44) }
        }
    }

    @ViewBuilder
    private func bubbleBackground(_ role: ChatMessage.Role) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if role == .user {
            shape.fill(LinearGradient(gradient: StrandPalette.goldGradient,
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            shape.fill(StrandPalette.surfaceRaised)
        }
    }

    private var typingBubble: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(StrandPalette.textTertiary).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(StrandPalette.surfaceRaised))
            Spacer(minLength: 44)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message your coach…", text: $draft, axis: .vertical)
                .font(StrandFont.body)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(StrandPalette.surfaceRaised))
                .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(StrandPalette.goldDeepText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(StrandPalette.accent))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.sending)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(StrandPalette.surfaceBase.opacity(0.9))
    }

    // MARK: Setup state

    private var setupCard: some View {
        StrandCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect your AI coach").font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("The coach runs against your own AI provider key and only sends what you allow. Add a provider and key to start chatting — everything stays under your control.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showSettings = true } label: {
                    Text("Set up coach")
                        .font(StrandFont.headline).foregroundStyle(StrandPalette.goldDeepText)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(StrandPalette.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        Task { await coach.send(t) }
    }
}
#endif
