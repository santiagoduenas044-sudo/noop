#if os(iOS)
import SwiftUI
import StrandDesign

/// Native Settings — migrated from the HTML prototype's grouped-card layout, wired to the REAL
/// preference keys and destinations instead of the mock's placeholder rows:
///  - Profile: the real `ProfileStore` (avatar/age/sex used for HR zones + baselines) plus the real
///    strap connection + battery (`LiveState`) — NOT a fake name/initials (NOOP is account-free by
///    design; there is no user-name field to show).
///  - Appearance: the real `AppearanceMode` (System/Light/Dark) and `ChartStyle` (Titanium/Classic)
///    toggles. The prototype's 6-dot "Accent" picker has no real backing (NOOP's brand accent is
///    fixed, Titanium & Gold), so it's replaced by the toggle that actually re-colours data — Chart
///    style — rather than faked.
///  - Notifications: a single nav row to the real, already-native Automations screen (wrist alerts,
///    illness watch, battery, strain target) — the comprehensive real settings for this, just named
///    differently than the mock's 3 inline toggles.
///  - Health sources / Data & privacy: nav rows to the real Devices / Apple Health / Data Sources /
///    Backup & Sync screens. The prototype's "App lock (Face ID/passcode)" has no real feature behind
///    it, so it's omitted (documented in What's New) rather than faked.
///  - Experimental: the real opt-in toggles that exist today (sleep staging V2, motion-aware wake,
///    auto-detect workouts, hydration) — replacing the mock's placeholder "Oura import"/"PPG estimate"
///    rows, neither of which is a real user-facing toggle (Oura is gated in the pairing wizard, not a
///    Settings switch; the PPG estimate work was withdrawn — see CLAUDE.md).
///  - About: the same visible build identifier (`BuildInfo`) as What's New.
/// The full classic `SettingsView` (units, HRV window, strap diagnostics, and everything this screen
/// doesn't restate) stays reachable, unchanged, via the "Advanced settings" row at the bottom.
struct PremiumSettingsView: View {
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var router: NavRouter
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(ChartStyle.storageKey) private var chartStyleRaw = ChartStyle.titanium.rawValue
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = true
    @AppStorage("selectedWhoopModel") private var selectedWhoopModelRaw = WhoopModel.whoop4.rawValue

    @AppStorage(PuffinExperiment.experimentalSleepV2Key) private var experimentalSleepV2Enabled = true
    @AppStorage(PuffinExperiment.motionAwareWakeKey) private var motionAwareWakeEnabled = false
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var autoDetectWorkoutsEnabled = false
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false

    @State private var showPrivacySheet = false

    private var whoopModel: WhoopModel { WhoopModel(rawValue: selectedWhoopModelRaw) ?? .whoop4 }
    private var appearance: AppearanceMode { AppearanceMode.resolve(appearanceRaw) }
    private var chartStyle: ChartStyle { ChartStyle.resolve(chartStyleRaw) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("top")
                    header
                    profileCard
                    appearanceSection
                    notificationsSection
                    healthSourcesSection
                    dataPrivacySection
                    experimentalSection
                    aboutSection
                    advancedRow
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 96)
            }
            .background(PremiumAmbient(tints: [StrandPalette.gold]).ignoresSafeArea())
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .sheet(isPresented: $showPrivacySheet) { privacySheet }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NOOP · ON-DEVICE").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Settings").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Profile (real: ProfileStore + LiveState)

    private var profileCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            HStack(spacing: 14) {
                Group {
                    if let img = profile.avatarImage {
                        img.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable().scaledToFit()
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(StrandPalette.hairline, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(whoopModel.displayName)")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(strapStatusLine)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                    if let pct = live.batteryPct { batteryRow(pct) }
                }
                Spacer()
                PremiumBadge(text: "On-device", tint: StrandPalette.recoveryColor(80))
            }
        }
    }

    private var strapStatusLine: String {
        var parts: [String] = [live.connected ? "Connected" : "Not connected"]
        parts.append("age \(profile.age)")
        return parts.joined(separator: " · ")
    }

    /// The strap's real, live battery reading (`LiveState.batteryPct`) as a tiny gauge bar next to its
    /// percentage — previously plain text buried in the status line.
    private func batteryRow(_ pct: Double) -> some View {
        let tint: Color = pct >= 50 ? StrandPalette.recoveryColor(80)
                         : pct >= 20 ? StrandPalette.gold : StrandPalette.metricRose
        return HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width * CGFloat(max(0, min(100, pct)) / 100)))
                }
            }
            .frame(width: 44, height: 6)
            Text("\(Int(pct))% battery").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
    }

    // MARK: - Appearance (real: AppearanceMode + ChartStyle)

    private var appearanceSection: some View {
        settingsGroup("Appearance") {
            HStack {
                Text("Theme").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(StrandPalette.gold)
            }
            groupDivider
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chart style").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Text("Re-colours gauges, rings and charts").font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
                Picker("Chart style", selection: $chartStyleRaw) {
                    ForEach(ChartStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(StrandPalette.gold)
            }
            groupDivider
            toggleRow(title: "Day-cycle sky", subtitle: "Sunrise/day/dusk/night backdrop behind Today",
                      isOn: $showDayCycleBackground)
        }
    }

    // MARK: - Notifications (real: routes to Automations, the actual native settings for this)

    private var notificationsSection: some View {
        settingsGroup("Notifications") {
            navRow(icon: "wand.and.stars", title: "Automations & Alerts",
                   subtitle: "Wrist alerts, illness watch, battery, strain target",
                   route: .automations)
        }
    }

    // MARK: - Health sources (real: Devices / Apple Health / Data Sources)

    private var healthSourcesSection: some View {
        settingsGroup("Health sources") {
            Button { router.openDevices() } label: {
                navRowLabel(icon: "antenna.radiowaves.left.and.right",
                            title: whoopModel.displayName,
                            subtitle: live.connected ? "Connected" : "Not connected · tap to pair")
            }
            .buttonStyle(.plain)
            groupDivider
            navRow(icon: "heart.fill", title: "Apple Health", subtitle: "Import steps & workouts",
                   route: .appleHealth)
            groupDivider
            navRow(icon: "externaldrive.fill", title: "Data Sources", subtitle: "CSV import, Mi Band, and more",
                   route: .dataSources)
        }
    }

    // MARK: - Data & privacy (real: Backup & Sync; static real privacy facts)

    private var dataPrivacySection: some View {
        settingsGroup("Data & privacy") {
            navRow(icon: "externaldrive.fill.badge.icloud", title: "Backup & Sync",
                   subtitle: ".noopbak · fully portable", route: .backupSync)
            groupDivider
            Button { showPrivacySheet = true } label: {
                navRowLabel(icon: "shield.fill", title: "Privacy",
                            subtitle: "No cloud. No account. No telemetry.")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Experimental (real opt-in toggles, replacing the mock's Oura/PPG placeholders)

    private var experimentalSection: some View {
        settingsGroup("Experimental") {
            toggleRow(title: "Experimental sleep staging (V2)",
                      subtitle: "Transparent cardiorespiratory re-staging",
                      isOn: $experimentalSleepV2Enabled)
            groupDivider
            toggleRow(title: "Motion-aware wake refinement",
                      subtitle: "Reclassifies scored WAKE using motion", isOn: $motionAwareWakeEnabled)
            groupDivider
            toggleRow(title: "Auto-detect workouts", subtitle: "Offers to save a sustained-HR window",
                      isOn: $autoDetectWorkoutsEnabled)
            groupDivider
            toggleRow(title: "Hydration tracker", subtitle: "Opt-in daily water logging",
                      isOn: $hydrationEnabled)
        }
    }

    // MARK: - About (real: BuildInfo)

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PremiumSectionHeader(title: "About")
            navRow(icon: "sparkles", title: "What's New",
                   subtitle: "Milestone \(BuildInfo.milestone) · what changed this build", route: .whatsNew)
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    PremiumInfoRow(label: "Version", value: BuildInfo.version)
                    PremiumInfoRow(label: "Build", value: BuildInfo.build)
                    PremiumInfoRow(label: "Commit", value: BuildInfo.commit)
                    PremiumInfoRow(label: "Built", value: BuildInfo.builtAt)
                }
            }
            Text("Your strap. Your data. Your machine. Offline, on-device, no cloud.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Advanced (preserves the full classic Settings screen, unchanged)

    private var advancedRow: some View {
        navRow(icon: "gearshape.2.fill", title: "Advanced settings",
               subtitle: "Units, HRV window, strap diagnostics, and everything else",
               route: .advancedSettings)
    }

    // MARK: - Shared row/group helpers

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PremiumSectionHeader(title: title)
            StrandCard { VStack(alignment: .leading, spacing: 12, content: content) }
        }
    }

    private var groupDivider: some View {
        Divider().overlay(StrandPalette.hairline)
    }

    private func toggleRow(title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(StrandPalette.gold)
        }
    }

    private func navRow(icon: String, title: String, subtitle: String? = nil,
                        route: MoreDestination) -> some View {
        NavigationLink(value: route) {
            navRowLabel(icon: icon, title: title, subtitle: subtitle)
        }
    }

    private func navRowLabel(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            PremiumIconTile(system: icon, tint: StrandPalette.gold, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Privacy sheet

    private var privacySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 40)).foregroundStyle(StrandPalette.gold)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("NOOP is fully offline and on-device. There is no server, no account, no cloud sync, and no telemetry. Your health data never leaves this machine.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    privacyFact("No cloud", "Data lives in on-device SQLite")
                    privacyFact("Account-free", "Nothing to sign up for")
                    privacyFact("No tracking", "Zero analytics that phone home")
                    privacyFact("Clean-room", "Interop with hardware you own")
                }
                Spacer()
            }
            .padding(20)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showPrivacySheet = false }
                }
            }
        }
    }

    private func privacyFact(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(StrandPalette.recoveryColor(80))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(subtitle).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}
#endif
