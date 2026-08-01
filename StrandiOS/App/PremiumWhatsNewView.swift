#if os(iOS)
import SwiftUI
import StrandDesign

/// Native What's New — the redesign milestone tracker, migrated from the HTML prototype.
/// Categorized ✅/🚧/🎨/❌/⚠️ with per-item screen, component, change and connection status,
/// plus the visible build identifier (version/build/commit/date from `BuildInfo`). This is
/// the redesign's milestone record; the app's separate release-notes `WhatsNewView` is
/// unrelated and preserved.
struct PremiumWhatsNewView: View {
    var onClose: (() -> Void)? = nil

    private struct Item { let screen: String; let component: String; let change: String; let status: Status }
    private enum Status { case connected, partial, prototype, notStarted, limitation
        var badge: (String, Color) {
            switch self {
            case .connected:  return ("Connected", StrandPalette.recoveryColor(80))
            case .partial:    return ("Partial", StrandPalette.effortColor)
            case .prototype:  return ("Prototype", StrandPalette.sleepDeep)
            case .notStarted: return ("Not started", StrandPalette.metricRose)
            case .limitation: return ("Known limit", StrandPalette.gold)
            }
        }
    }
    private struct Group { let emoji: String; let name: String; let tint: Color; let items: [Item] }

    private var groups: [Group] {
        [Group(emoji: "✅", name: "Implemented & connected", tint: StrandPalette.recoveryColor(80), items: [
            Item(screen: "Home", component: "Recovery hero + vitals + drivers", change: "Native on real DailyMetric.", status: .connected),
            Item(screen: "Readiness", component: "Contributors + forecast", change: "Real HRV/RHR/sleep/skin-temp.", status: .connected),
            Item(screen: "Coach", component: "Chat on real AICoachEngine", change: "Live send/history/typing.", status: .connected),
            Item(screen: "Trends", component: "Metric picker + charts", change: "Real repo.days series.", status: .connected),
            Item(screen: "Insights", component: "“Why” cards", change: "Computed from real trends.", status: .connected),
            Item(screen: "Journal", component: "Mood + grouped behaviour log", change: "Real MoodStore + JournalCatalogStore; FAB \"Log journal\" opens it natively.", status: .connected),
            Item(screen: "Settings", component: "Build identifier", change: "Version/build/commit/date visible.", status: .connected),
        ]),
        Group(emoji: "🚧", name: "Partially connected", tint: StrandPalette.effortColor, items: [
            Item(screen: "Sleep", component: "Stage breakdown", change: "Real stage proportions; time-resolved hypnogram pending.", status: .partial),
            Item(screen: "Heart", component: "Live pulse + day HR", change: "Real HR; ECG + zone-shaded ribbon pending.", status: .partial),
        ]),
        Group(emoji: "🎨", name: "Prototype only", tint: StrandPalette.sleepDeep, items: [
            Item(screen: "Settings", component: "Full prototype layout", change: "Native uses classic + build card.", status: .prototype),
        ]),
        Group(emoji: "❌", name: "Not started", tint: StrandPalette.metricRose, items: [
            Item(screen: "Navigation", component: "5-tab bar (Home·Sleep·Heart·Coach·Trends)", change: "Heart/Coach reachable via More for now.", status: .notStarted),
        ]),
        Group(emoji: "⚠️", name: "Known limitations", tint: StrandPalette.gold, items: [
            Item(screen: "Global", component: "Animation parity", change: "Count-ups / draw-on / ripples are HTML-only so far.", status: .limitation),
            Item(screen: "Coach", component: "AI provider key", change: "Chat needs your own API key (real requirement).", status: .limitation),
            Item(screen: "Journal", component: "Quick-log tiles + photo + note", change: "The HTML mock's canned Training/Caffeine/Alcohol option sheets, photo attach, and freeform day note have no real on-device field, so they're intentionally left out rather than faked. Real behaviours (yes/no + numeric, grouped) are fully wired.", status: .limitation),
        ])]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                versionCard
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in groupBlock(g) }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
        }
        .background(PremiumAmbient(tints: [StrandPalette.gold, StrandPalette.sleepDeep]).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MILESTONE \(BuildInfo.milestone)").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("What’s New").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NOOP Premium").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    PremiumBadge(text: "M\(BuildInfo.milestone)", tint: StrandPalette.gold)
                }
                PremiumInfoRow(label: "Version", value: BuildInfo.version)
                PremiumInfoRow(label: "Build", value: BuildInfo.build)
                PremiumInfoRow(label: "Commit", value: BuildInfo.commit)
                PremiumInfoRow(label: "Built", value: BuildInfo.builtAt)
                PremiumInfoRow(label: "Prototype", value: BuildInfo.prototypeVersion)
            }
        }
    }

    private func groupBlock(_ g: Group) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PremiumSectionHeader(title: "\(g.emoji) \(g.name)", trailing: "\(g.items.count)")
            ForEach(Array(g.items.enumerated()), id: \.offset) { _, it in
                StrandCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            PremiumBadge(text: it.screen, tint: g.tint)
                            Spacer()
                            PremiumBadge(text: it.status.badge.0, tint: it.status.badge.1)
                        }
                        Text(it.component).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text(it.change).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
#endif
