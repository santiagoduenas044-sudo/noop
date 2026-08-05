#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    @EnvironmentObject private var repo: Repository
    /// Cross-screen navigation requests (e.g. Live → "Manage devices"). Devices isn't a tab — it lives
    /// behind the More list — so a request presents it as a sheet, matching the quick-action screens.
    @EnvironmentObject private var router: NavRouter

    /// Which quick-action screen the centre FAB is presenting (nil = sheet closed).
    @State private var quickAction: QuickAction?
    /// Presents the Devices manager (pair / switch bands) when a screen asks the shell to open it.
    @State private var showDevices = false
    /// A routed v5 pillar screen (Insights hub / Lab Book / fused record / Rhythm) presented as a sheet
    /// when a hub row deep-links to it via NavRouter. nil = closed.
    @State private var routedPillar: NavRouter.Destination?
    /// Selected tab — bound so tab switches can crossfade (README §Motion: ~240ms opacity swap
    /// between tab roots, calm easing). Defaults to Today.
    @State private var selectedTab: Int = 0
    /// One `NavigationPath` per tab, indexed by tab tag. Re-tapping the already-active tab pops
    /// that tab's stack to its root (#135) by clearing its path — an animated pop that leaves the
    /// root view alive, so an at-root re-tap keeps scroll position and never re-runs `.task`
    /// (#198; the #197 resetID/`.id()` rebuild reset both). Requires the tab roots' first-hop
    /// links to push `TabRoute`/`MoreDestination` VALUES — closure-destination links bypass the path.
    @State private var tabPaths: [NavigationPath] = Array(repeating: NavigationPath(), count: 6)
    /// One scroll-to-top token per tab. Bumped when the user re-taps the active tab while it's ALREADY
    /// at its root — the other half of the iOS convention #197/#198 left unserved (an at-root re-tap was
    /// a no-op). Threaded into each tab's root via `\.scrollToTopSignal`; ScreenScaffold / LiquidTodayView
    /// scroll to their top anchor when their tab's token changes.
    @State private var scrollTop: [Int] = Array(repeating: 0, count: 6)
    /// Which More-tab groups are expanded (S2). Insights + Body stay open at rest; Data + App collapse to
    /// just their header until tapped. Persisted (#860 item 2): the user's open/closed choice must SURVIVE
    /// leaving and re-entering the More tab (and relaunch), not reset to the seed every visit. Backed by an
    /// `@AppStorage` CSV string (keyed identically to the Android `MoreSectionPrefs`), bridged to a
    /// `Set<String>` through `MoreSectionPrefs` so the section logic below is unchanged.
    @AppStorage(MoreSectionPrefs.storageKey) private var expandedMoreSectionsCSV = MoreSectionPrefs.defaultCSV
    private var expandedMoreSections: Set<String> { MoreSectionPrefs.decode(expandedMoreSectionsCSV) }

    /// The Home tab root. On iOS the Premium Home (the native rebuild of the approved prototype) is now
    /// the ONLY Home — it is no longer gated behind the legacy `noop.liquidTodayEnabled` toggle. That
    /// toggle survives a sideload from a prior install, so a user who once switched it off would upgrade
    /// to the new build and find every screen redesigned EXCEPT Home, which silently fell back to the
    /// classic `TodayView` (the reported "Home is still the old one"). The redesign is the product, so
    /// Home is unconditional here; the classic dashboard stays reachable via the More → Advanced flow.
    private var todayTabRoot: some View { PremiumHomeView() }

    init() {
        // Plain Titanium bar: pin the background to `surfaceBase` and clear the system
        // selection-indicator tint so there is NO gold/accent pill behind the selected
        // icon — the gold `.tint` below colours only the selected icon + label, nothing
        // is filled behind it. (UIKit derives a selection-indicator fill from the tint
        // unless it's explicitly cleared.)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(StrandPalette.surfaceBase)
        appearance.selectionIndicatorTintColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        // The native TabView keeps every existing destination + system gesture; a custom floating
        // glass-capsule bar (FloatingTabBar) replaces its native chrome — the native TabView still
        // drives content + per-tab nav state, only its bar is hidden. The quick-action "+" lives in
        // each screen's own header, not in this bar (see FloatingTabBar's doc comment).
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                tab(todayTabRoot, "Home", "square.grid.2x2", path: $tabPaths[0], scrollSignal: scrollTop[0]).tag(0)
                tab(PremiumSleepView(), "Sleep", "bed.double", path: $tabPaths[1], scrollSignal: scrollTop[1]).tag(1)
                tab(PremiumHeartView(), "Heart", "heart.fill", path: $tabPaths[2], scrollSignal: scrollTop[2]).tag(2)
                tab(PremiumCoachView(), "Coach", "sparkles", path: $tabPaths[3], scrollSignal: scrollTop[3]).tag(3)
                tab(PremiumTrendsView(), "Trends", "chart.line.uptrend.xyaxis", path: $tabPaths[4], scrollSignal: scrollTop[4]).tag(4)
                moreTab(path: $tabPaths[5], scrollSignal: scrollTop[5]).tag(5)
            }
            .tint(StrandPalette.accent)
            .toolbar(.hidden, for: .tabBar)
            // Tab crossfade — README §Motion: ~240ms opacity swap between tab roots, global calm
            // easing cubic-bezier(0.22,1,0.36,1).
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: selectedTab)
            // Swipe-anywhere-to-change-tabs was removed: it fired on ordinary vertical/diagonal scroll
            // gestures inside a screen's content (e.g. scrolling Home) and switched tabs unintentionally.
            // Tab changes now go ONLY through the explicit FloatingTabBar taps below.

            FloatingTabBar(selection: $selectedTab, onReselect: { tag in
                // Re-tapping the active tab refreshes that page's data (2026-07-02) and, from a
                // subpage, pops that tab's stack back to its root (#135) — an animated pop via the
                // path, not a rebuild. At the root the pop is skipped, so scroll position survives
                // and the refresh doesn't double with a re-run of the root's `.task` (#198).
                Task { await repo.refresh() }
                if !tabPaths[tag].isEmpty {
                    tabPaths[tag] = NavigationPath()   // on a subpage: animated pop back to the root
                } else {
                    scrollTop[tag] += 1                // already at root: scroll to the top (#198 follow-up)
                }
            })
        }
        .task {
            await repo.refresh()
            // Backup & Sync: on-launch catch-up (see RootView). Detached + utility priority so a
            // 100MB+ whole-DB ZIP never blocks startup; gated on the auto toggle (default OFF). (Must-fix #4.)
            let backupRepo = repo
            Task.detached(priority: .utility) {
                await FolderBackup.catchUpIfDue(checkpoint: { await backupRepo.checkpointForBackup() })
            }
        }
        // Quick-action sheet presents with the calm easing (~0.42s) per the README sheet spec —
        // the easing is applied where `quickAction` is set (see `presentQuickAction`), keeping the
        // animation scoped to the sheet rather than the whole shell.
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
        // Live's "Manage devices" affordance (and any future cross-screen link to Devices) routes here:
        // present the Devices manager in its own nav stack, the same way the quick-action screens do.
        .sheet(isPresented: $showDevices) {
            devicesScreen
        }
        // v5 pillar deep-links (Insights hub / Lab Book / fused record / Rhythm) present as a sheet in
        // their own nav stack — the same idiom the quick-action + Devices screens use on iPhone.
        .sheet(item: $routedPillar) { dest in
            pillarScreen(dest)
        }
        // Honour a router request: Devices keeps its dedicated sheet; the v5 pillars route through the
        // shared pillar sheet. Cleared so the same tap can fire again later.
        .onChange(of: router.requestedDestination) { _, dest in
            switch dest {
            case .devices:
                showDevices = true
                router.requestedDestination = nil
            case .insightsHub, .labBook, .fusedRecord, .rhythm:
                routedPillar = dest
                router.requestedDestination = nil
            case .trends:
                // Trends is a primary tab on iPhone (not a pillar sheet) — switch to it.
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 4 }
                router.requestedDestination = nil
            case .activeWorkout:
                // The Today active-workout indicator opens Live through the quick-action Live sheet; once
                // it's up, LiveView consumes the one-shot `presentActiveWorkout` flag and presents the
                // in-exercise screen. Calm sheet easing, matching the other quick-action presents.
                withAnimation(Self.sheetEase) { quickAction = .live }
                router.requestedDestination = nil
            case .liveSession:
                // Live Sessions is presented from Today's own Start entry (a cover, not a routed sheet),
                // so a deep-link lands on the Today tab where that entry lives.
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 0 }
                router.requestedDestination = nil
            case .journal:
                // The #627 Today journal widget opens the journal through the quick-action Journal sheet
                // (InsightsView), matching the FAB's "Log journal" action. Calm sheet easing.
                withAnimation(Self.sheetEase) { quickAction = .journal }
                router.requestedDestination = nil
            case nil:
                break
            }
        }
        // A screen's top-bar "+" routes here: open the quick-action sheet, then clear the flag.
        .onChange(of: router.quickActionsRequested) { _, req in
            if req {
                withAnimation(Self.sheetEase) { quickAction = .menu }
                router.quickActionsRequested = false
            }
        }
    }

    /// A routed v5 pillar screen wrapped in its own nav stack + Done button (mirrors `quickScreen`).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        NavigationStack {
            Group {
                switch dest {
                case .insightsHub: InsightsHubView()
                case .labBook: LabBookView()
                case .fusedRecord: FusedRecordHost()
                case .rhythm: RhythmHost(onClose: { routedPillar = nil })
                case .devices: DevicesView()
                // .trends is never presented as a pillar sheet on iPhone (it's a primary tab — the
                // requestedDestination handler switches `selectedTab` instead), but the switch must stay
                // exhaustive. Fall back to Trends inside the sheet host if it ever arrives here.
                case .trends: TrendsView()
                // .activeWorkout routes through the quick-action Live sheet (handled above); this keeps the
                // switch exhaustive and falls back to Live if it ever reaches the pillar host.
                case .activeWorkout: LiveView()
                // .liveSession routes to the Today tab (handled above — its Start entry owns the cover);
                // this keeps the switch exhaustive and falls back to Today if it ever reaches the host.
                case .liveSession: LiquidTodayView()
                // .journal opens through the quick-action Journal sheet (handled above); this keeps the
                // switch exhaustive and falls back to the native Journal screen if it ever reaches here.
                case .journal: PremiumJournalView()
                }
            }
            // The Trends/Today fallbacks above emit TabRoute value pushes (#198), which need a
            // destination registered in THIS sheet's stack to resolve.
            .tabRouteDestinations()
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // #1027: same fix as quickScreen — the pillar screens draw the full-bleed liquid sky, so a
            // transparent nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { routedPillar = nil }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    /// Calm-easing curve (cubic-bezier(0.22,1,0.36,1)) at the README sheet-present duration.
    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    // MARK: - Quick-action sheet

    /// Routes a chosen quick action to the existing screen, or shows the action menu itself.
    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            QuickActionSheet { picked in
                // Swap the menu for the chosen destination on the next runloop so the sheet
                // re-presents cleanly (avoids dismiss/re-present races). Calm easing on re-present.
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { quickAction = picked }
                }
            }
            .presentationDetents([.height(344)])
            .presentationDragIndicator(.hidden)
        case .live:
            quickScreen(LiveView())
        case .workout:
            quickScreen(WorkoutsView())
        case .journal:
            quickScreen(PremiumJournalView())
        case .breathe:
            quickScreen(BreathingView())
        }
    }

    /// Wraps a routed quick-action screen in its own nav stack so it has a title bar + the
    /// shared surface background, matching how the More-tab links present these same views.
    private func quickScreen<V: View>(_ view: V) -> some View {
        NavigationStack {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: these screens draw a full-bleed liquid sky (ScreenScaffold topBackground) that runs
                // edge-to-edge under a transparent bar — exactly how the tab roots present it. An OPAQUE
                // surfaceBase toolbar background sat on top of that sky and, as the content scrolled up, its
                // extended status-bar band CLIPPED the sky + the in-content header ("Live Body Console").
                // Hiding the bar background lets the sky stay continuous under the floating Done button.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { quickAction = nil }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    /// The Devices manager wrapped in its own nav stack + Done button (mirrors `quickScreen`, but
    /// dismisses the dedicated `showDevices` sheet rather than the quick-action item).
    private var devicesScreen: some View {
        NavigationStack {
            DevicesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: same fix as quickScreen — Devices draws the full-bleed liquid sky, so a transparent
                // nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    private func tab<V: View>(_ view: V, _ title: LocalizedStringKey, _ icon: String,
                              path: Binding<NavigationPath>, scrollSignal: Int) -> some View {
        // Each primary tab gets its OWN NavigationStack so the in-content NavigationLinks (e.g. the Today
        // dashboard card rows) both navigate AND render opaque. An ORPHANED NavigationLink (no
        // NavigationStack ancestor) renders its whole label in a disabled/translucent state — that was
        // washing the Today cards over the hero scene and dimming their text to grey (2026-06-23).
        // The root view hides the system nav bar (each screen draws its own in-content header); pushed
        // detail screens get their own nav bar + back button. The stack is bound to the tab's path so a
        // re-tap of the active tab can pop it to the root (#135/#198); the roots' first-hop links push
        // TabRoute values, registered here ONCE per stack (a double registration double-pushes, #38).
        NavigationStack(path: path) {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .tabRouteDestinations()
                // iOS-only Premium deep screens (metric detail, energy, blood oxygen, strain). Separate
                // registration from the shared TabRoute one above so the iOS-only views never touch macOS.
                .premiumRouteDestinations()
        }
        // Drive this tab's root scroll-to-top on an at-root re-tap (#198 follow-up); read by ScreenScaffold
        // / LiquidTodayView inside. Only THIS tab's token changes on its reselect, so the others don't scroll.
        .environment(\.scrollToTopSignal, scrollSignal)
        .toolbar(.hidden, for: .tabBar)   // we draw our own FloatingTabBar
        .tabItem { Label(title, systemImage: icon) }
    }

    // The "More" tab is the app's catch-all index. It was a plain SwiftUI `List` with system large-title
    // + system title-case section headers, so it didn't match any other page (which all use ScreenScaffold
    // + SectionHeader's UPPERCASE overline + the 28pt section rhythm). Rebuilt on the shared page chrome:
    // ScreenScaffold for the title1 "More" + subtitle, a `SectionHeader` overline per group, and the group's
    // rows in a single grouped NoopCard with hairline dividers — the same row idiom Settings/Health use.
    private func moreTab(path: Binding<NavigationPath>, scrollSignal: Int) -> some View {
        NavigationStack(path: path) {
            ScreenScaffold(title: "More", subtitle: "Everything else, one tap away",
                           onRefresh: { await repo.refresh() },
                           topBackground: liquidScaffoldSky()) {
                moreSection("Insights") {
                    // Coach is now a primary tab (Home·Sleep·Heart·Coach·Trends); no More row needed.
                    MoreRow("What Moves You", "wand.and.sparkles", .insightsHub)
                    MoreRow("Intelligence", "brain.head.profile", .intelligence)
                    MoreRow("Insights", "lightbulb.fill", .insights)
                    MoreRow("Behaviour Log", "list.bullet.clipboard.fill", .behaviourLog)
                    MoreRow("Explore", "square.grid.2x2.fill", .explore)
                    MoreRow("Compare", "rectangle.split.2x1.fill", .compare)
                }
                moreSection("Body") {
                    // Heart is now a primary tab (Home·Sleep·Heart·Coach·Trends); no More row needed.
                    MoreRow("Live", "waveform.path.ecg", .live)
                    MoreRow("Workouts", "figure.run", .workouts)
                    MoreRow("Lab Book", "books.vertical.fill", .labBook)
                    MoreRow("Stress", "bolt.heart.fill", .stress)
                    MoreRow("Breathe", "wind", .breathe)
                    MoreRow("Intervals", "timer", .intervals)
                    // Experimental beat-to-beat regularity visualization — self-gates on its own consent.
                    MoreRow("Rhythm", "waveform.path", .rhythm)
                }
                moreSection("Data") {
                    MoreRow("Your Data, Fused", "square.stack.3d.up.fill", .fusedRecord)
                    MoreRow("Apple Health", "heart.fill", .appleHealth)
                    MoreRow("Mi Band", "figure.walk.motion", .miBand)
                    MoreRow("Data Sources", "externaldrive.fill", .dataSources)
                    MoreRow("Backup & Sync", "externaldrive.fill.badge.icloud", .backupSync)
                    // #155: HealthKit-free Apple Health path for sideloaded installs (Siri Shortcut
                    // reads the opt-in Documents/noop_sync.txt drop file).
                    MoreRow("Shortcuts Export", "square.and.arrow.up.fill", .shortcutsExport)
                }
                moreSection("App") {
                    MoreRow("What’s New", "sparkles", .whatsNew)
                    // #805/#811: the v7.3.1 #766 alarm consolidation moved Smart Alarm under a single
                    // "Alarms" sidebar entry (RootView .smartAlarm) but the regression dropped the row
                    // from the iPhone More list, leaving Alarms unreachable on iPhone. Restore it here
                    // (route to SmartAlarmView, the cross-platform iOS/macOS surface).
                    //
                    // Notifications (RootView .notifications) is deliberately NOT added: that screen is
                    // macOS-only (it picks which Mac apps tap your wrist via NSWorkspace, imports AppKit,
                    // and project.yml excludes Screens/NotificationSettingsView.swift from the iOS target),
                    // so it can't compile or apply on iPhone. iPhone's wrist-alert controls live on the
                    // Automations screen instead. Its absence from the iPhone More list is correct.
                    MoreRow("Alarms", "alarm.fill", .alarms)
                    MoreRow("Automations", "wand.and.stars", .automations)
                    // The Test Centre (the diagnostics + bug-report hub) gets a first-class home here, not
                    // just buried in Settings, so the feedback loop is one tap from the More tab.
                    MoreRow("Test Centre", "stethoscope", .testCentre)
                    MoreRow("Siri & Shortcuts", "mic.fill", .siriShortcuts)
                    MoreRow("Settings", "gearshape.fill", .settings)
                }
            }
            .toolbar(.hidden, for: .tabBar)   // we draw our own FloatingTabBar
            // The rows push MoreDestination VALUES so a re-tap of the More tab can pop them off the
            // bound path (#135/#198). Each destination keeps the per-screen wrapper the rows used to
            // apply inline (surfaceBase background, inline title bar, hidden bar background):
            // #1027 — a pushed sky-scaffold screen (Live, Workouts, Health, …) draws a full-bleed liquid
            // sky; an opaque surfaceBase nav-bar band sat over it and clipped the top on scroll. A hidden
            // bar background keeps the sky edge-to-edge. On the flat (no-sky) screens this is visually
            // identical at rest — the destination's own surfaceBase background shows through the bar.
            .navigationDestination(for: MoreDestination.self) { route in
                route.destination
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            // The More index also reaches the iOS-only Premium deep screens (e.g. a metric row deep-links
            // into a detail); register the same destinations on its stack.
            .premiumRouteDestinations()
        }
        // Scroll the More index to the top on an at-root re-tap (#198 follow-up); read by its ScreenScaffold.
        .environment(\.scrollToTopSignal, scrollSignal)
        .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
    }

    /// One titled, COLLAPSIBLE group in the More index (S2): the app's overline (UPPERCASE) becomes a
    /// tappable header with a disclosure chevron; tapping it expands/collapses the grouped rows card.
    /// Insights + Body default open, Data + App default collapsed (the `expandedMoreSections` seed) so the
    /// list is shorter at rest without dropping a single row. The grouped card is unchanged: a single
    /// `NoopCard` holding a `VStack(spacing: 0)` whose `MoreRow`s draw their own hairlines, clipped to the
    /// card's rounded shape so the last divider is trimmed inside the corners. Same idiom Settings/Health use.
    @ViewBuilder
    private func moreSection<Rows: View>(_ title: String,
                                         @ViewBuilder rows: @escaping () -> Rows) -> some View {
        let isOpen = expandedMoreSections.contains(title)
        VStack(alignment: .leading, spacing: 10) {
            // Tappable overline header: the same ALL-CAPS tracked label as before, now with a trailing
            // chevron that rotates open. A plain Button (not a SwiftUI DisclosureGroup) so the header keeps
            // the exact strandOverline styling and the card layout below stays identical to before.
            Button {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                    // Persist the toggle via the CSV-backed @AppStorage so the choice survives leaving and
                    // re-entering the More tab and relaunch (#860 item 2). MoreSectionPrefs owns encode/decode.
                    var open = expandedMoreSections
                    if isOpen { open.remove(title) } else { open.insert(title) }
                    expandedMoreSectionsCSV = MoreSectionPrefs.encode(open)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title).strandOverline()
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(isOpen ? String(localized: "Expanded") : String(localized: "Collapsed")))
            .accessibilityHint(Text(isOpen ? String(localized: "Double tap to collapse") : String(localized: "Double tap to expand")))

            if isOpen {
                // Zero internal padding so each MoreRow owns its own comfortable insets + height; the rows
                // supply their own hairline separators (drawn at the bottom of every row but the last via the
                // divider overlay) so the group reads as one continuous grouped list, matching Settings/Health.
                NoopCard(padding: 0) {
                    VStack(spacing: 0) { rows() }
                        // Clip the rows column to the card's rounded shape so the last row's bottom hairline is
                        // trimmed inside the corners (the card draws its surface in the BACKGROUND and doesn't
                        // clip content itself, so without this the final divider would run past the rounded edge).
                        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                }
            }
        }
    }
}

/// Every screen the More index links to, as a `Hashable` value the tab's `NavigationPath` can carry
/// (#198): a closure-destination push would bypass the path and be un-poppable on tab re-tap. The
/// per-screen chrome the old inline links applied lives at the single `navigationDestination(for:)`
/// registration in `moreTab`.
/// Not `private`: `PremiumSettingsView` (a separate file) pushes its own rows onto the SAME More-tab
/// NavigationStack via `NavigationLink(value: MoreDestination.xxx)`, resolved by this enum's
/// `.navigationDestination(for:)` registration in `moreTab()` below — that registration covers the
/// whole stack, including views pushed deeper (like a Settings row pushing Apple Health).
enum MoreDestination: Hashable {
    // Coach and Heart are primary tabs (Home·Sleep·Heart·Coach·Trends), not More destinations.
    case insightsHub, intelligence, insights, behaviourLog, explore, compare
    case live, workouts, labBook, stress, breathe, intervals, rhythm
    case fusedRecord, appleHealth, miBand, dataSources, backupSync, shortcutsExport
    case alarms, automations, testCentre, siriShortcuts, settings, advancedSettings, whatsNew

    @ViewBuilder var destination: some View {
        switch self {
        case .insightsHub:     InsightsHubView()
        case .intelligence:    IntelligenceView()
        case .insights:        PremiumInsightsView()
        // The classic full Insights screen (behaviour effect ranking + activity cost + relationships,
        // plus its own embedded journal/mood/caffeine logging) — kept reachable here, unchanged, now that
        // the FAB's "Log journal" quick action points at the dedicated native `PremiumJournalView` instead.
        case .behaviourLog:    InsightsView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .live:            LiveView()
        case .workouts:        WorkoutsView()
        case .labBook:         LabBookView()
        case .stress:          StressView()
        case .breathe:         BreathingView()
        case .intervals:       IntervalTimerView()
        case .rhythm:          RhythmHost()
        case .fusedRecord:     FusedRecordHost()
        case .appleHealth:     AppleHealthView()
        case .miBand:          XiaomiBandView()
        case .dataSources:     DataSourcesView()
        case .backupSync:      BackupSyncView()
        case .shortcutsExport: ShortcutExportSettingsView()
        case .alarms:          SmartAlarmView()
        case .automations:     AutomationsView()
        case .testCentre:      TestCentreView()
        case .siriShortcuts:   SiriShortcutsSettingsView()
        // The prototype-migrated native Settings home (profile, appearance, notifications, health
        // sources, data & privacy, experimental, about) — real toggles/nav rows throughout.
        case .settings:        PremiumSettingsView()
        // The full classic Settings screen (units, HRV window, strap diagnostics, and everything else
        // PremiumSettingsView doesn't restate) — kept reachable, unchanged, via a row inside Premium Settings.
        case .advancedSettings: SettingsView()
        case .whatsNew:        PremiumWhatsNewView()
        }
    }
}

/// One tappable destination row in the More index. A `NavigationLink` whose label is the standard app row:
/// the SF Symbol icon tinted `StrandPalette.accent`, the title in the body text colour, a `Spacer`, and a
/// trailing `chevron.right` in `textTertiary`. ~44pt min height + the card's row insets keep the whole row a
/// comfortable tap target.
private struct MoreRow: View {
    let title: LocalizedStringKey
    let icon: String
    let route: MoreDestination

    init(_ title: LocalizedStringKey, _ icon: String, _ route: MoreDestination) {
        self.title = title; self.icon = icon; self.route = route
    }

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                // Pin the icon to the accent explicitly. A plain inherited tint gets re-resolved by iOS to
                // its default blue a beat after first render — so the icons flashed green→blue (#184). The
                // explicit foregroundStyle on the image overrides that; the title keeps the primary colour.
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Hairline under every row; the grouped container clips the last one's overflow so the bottom
            // edge stays clean (the divider sits inside the card's rounded corners).
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick actions (centre FAB)

/// The destinations the centre FAB can present. `.menu` is the action sheet itself; the rest
/// route to existing screens. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe
    var id: Int { rawValue }
}

/// The bottom sheet of quick actions presented by the centre FAB. Spec bottom sheet: surfaceOverlay
/// fill, gold hairline top edge, grab handle, three flat action rows that route to existing screens.
private struct QuickActionSheet: View {
    /// Called with the picked destination (the host swaps the menu for that screen).
    let onPick: (QuickAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle (36×4) in the slate hairline tone.
            Capsule()
                .fill(StrandPalette.hairlineStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("QUICK ACTIONS")
                .font(StrandFont.overline)
                .tracking(1.6)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                row("Live HR", icon: "waveform.path.ecg", tint: StrandPalette.metricRose) { onPick(.live) }
                row("Start workout", icon: "figure.run", tint: StrandPalette.effortColor) { onPick(.workout) }
                row("Log journal", icon: "square.and.pencil", tint: StrandPalette.accent) { onPick(.journal) }
                row("Breathe", icon: "wind", tint: StrandPalette.restColor) { onPick(.breathe) }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            StrandPalette.surfaceOverlay
                .overlay(alignment: .top) {
                    // Gold hairline top edge per the bottom-sheet spec.
                    Rectangle()
                        .fill(StrandPalette.gold.opacity(0.35))
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }

    /// One flat action row: hued line-icon tile + title, inset surface, hairline border.
    private func row(_ title: LocalizedStringKey, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(StrandPalette.surfaceInset))
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating tab bar

/// The signature bottom bar: one frosted "glass" capsule with the prototype's 5 primary tabs
/// (Home·Sleep·Heart·Coach·Trends) plus a 6th "More" tab for the rest of NOOP's real screens, which
/// the prototype's smaller mock never needed to represent. Real iOS 26 Liquid Glass where available,
/// a `.ultraThinMaterial` fallback below. Replaces the hidden native tab bar. The quick-action "+"
/// lives in the top-right of each screen's header (balancing the profile avatar on the left), not in
/// this bar.
private struct FloatingTabBar: View {
    @Binding var selection: Int
    /// Fires when the user taps the ALREADY-active tab (2026-07-02: re-tap should refresh).
    var onReselect: (Int) -> Void = { _ in }

    private struct Item: Identifiable { let title: LocalizedStringKey; let icon: String; let tag: Int; var id: Int { tag } }
    private let nav = [Item(title: "Home", icon: "square.grid.2x2", tag: 0),
                       Item(title: "Sleep", icon: "bed.double", tag: 1),
                       Item(title: "Heart", icon: "heart.fill", tag: 2),
                       Item(title: "Coach", icon: "sparkles", tag: 3),
                       Item(title: "Trends", icon: "chart.line.uptrend.xyaxis", tag: 4),
                       Item(title: "More", icon: "ellipsis", tag: 5)]

    var body: some View {
        // One frosted glass bar, six evenly-spaced tabs.
        HStack(spacing: 2) {
            ForEach(nav) { tabButton($0) }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .liquidGlass(in: Capsule())
        // Over the liquid Today the sky ends at ~340pt, so the bar floats on flat opaque surfaceBase —
        // a blur material has nothing to dissolve and hardens into a solid lozenge (2026-07-02:
        // "clips into a solid shape"). A faint translucent scrim INSIDE the same Capsule keeps the pill
        // reading as tinted glass, not a slab, even against dead-flat colour.
        .background(.white.opacity(0.06), in: Capsule())
        // Soft top-lit rim instead of one hard hairline, so there's no crisp cut-out edge.
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
        )
        // Lighter, wider shadow: real elevation without stamping a dark halo on the flat canvas.
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func tabButton(_ item: Item) -> some View {
        let active = selection == item.tag
        return Button {
            if active {
                onReselect(item.tag)
            } else {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selection = item.tag }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: active ? .semibold : .regular))
                Text(item.title)
                    .font(.system(size: 9.5, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(active ? StrandPalette.accent : StrandPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

}

// MARK: - Liquid Glass (iOS 26) with a Material fallback

private extension View {
    /// Real iOS 26 Liquid Glass where available; `.ultraThinMaterial` on iOS 17–25 — a clean
    /// blended degrade so the bar stays modern on new OSes without breaking older ones.
    @ViewBuilder func liquidGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
#endif
