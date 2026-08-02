#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Native Journal — migrated from the HTML prototype's mood + log grid + behaviours mock, but
/// wired to the REAL stores instead of the prototype's canned data: mood check-in (`MoodStore` /
/// `repo.saveMood`/`repo.mood`), and the grouped yes/no + numeric behaviour catalog
/// (`JournalCatalogStore` / `repo.saveJournalAnswer`/`saveJournalNumeric`/`clearJournalAnswer`) —
/// the same storage `JournalLogCard` (classic Insights) and `MindSection` use, so answers logged
/// here and there are the exact same rows. The prototype's "quick log tiles" (Training/Caffeine/
/// Alcohol/… with canned option sheets) and free-text "Recovery note" have no backing field in the
/// real schema — behaviours are the catalog's yes/no or numeric items, and there's no generic
/// per-day note column — so those are intentionally left out rather than faked. Photo attach is
/// the same: no on-device store for it, so it's omitted.
struct PremiumJournalView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var router: NavRouter
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @StateObject private var catalog = JournalCatalogStore()

    @State private var dayOffset = 0
    @State private var importedQuestions: [String] = []
    @State private var answers: [String: Bool] = [:]
    @State private var numericAnswers: [String: Double] = [:]
    @State private var selectedMood: Int?
    private struct MoodPoint: Identifiable { let day: String; let value: Double; var id: String { day } }
    /// Real check-in history from `Repository.moodSeries` (the same mood rows `moodFace` writes),
    /// oldest→newest — never fabricated, empty until the user has logged at least two days.
    @State private var moodHistory: [MoodPoint] = []
    @State private var editing = false
    @State private var customDraft = ""
    @State private var customIsNumeric = false
    @State private var customGroup: JournalGroup = .other
    @State private var renaming: JournalCatalogItem?
    @State private var renameDraft = ""
    @AppStorage("journal.collapsedGroups") private var collapsedGroupsRaw = ""

    /// Same bounded, chronological range as the classic `JournalLogCard` (#656): Tomorrow through
    /// six days back.
    private static let dayOffsets: [Int] = Array((-1...6).reversed())

    private var dayKey: String {
        Repository.localDayKey(
            Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date())
    }

    private var resolved: [JournalCatalogItem] {
        catalog.resolvedItems(imported: importedQuestions, includeHidden: editing)
    }

    private func items(in group: JournalGroup) -> [JournalCatalogItem] {
        resolved.filter { $0.group == group }
            .sorted { ($0.sortIndex, $0.display) < ($1.sortIndex, $1.display) }
    }

    private var collapsedGroups: Set<String> {
        Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
    }

    private func toggleCollapsed(_ group: JournalGroup) {
        var set = collapsedGroups
        if set.contains(group.rawValue) { set.remove(group.rawValue) } else { set.insert(group.rawValue) }
        collapsedGroupsRaw = set.sorted().joined(separator: ",")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("top")
                    header
                    dayPicker
                    moodCard
                    moodHistoryCard
                    logSection
                    addCustomCard
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 96)
            }
            .background(PremiumAmbient(tints: [StrandPalette.gold]).ignoresSafeArea())
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
        }
        .task(id: repo.refreshSeq) { await load() }
        .task(id: dayOffset) { await loadDay() }
        .sheet(item: $renaming) { item in renameSheet(item) }
        // #656: honour a day the Today journal widget deep-linked to (tapping a bar opens the journal
        // at THAT day). Consumed once on arrival, then cleared.
        .onAppear {
            if let day = router.pendingJournalDayOffset {
                dayOffset = day
                router.pendingJournalDayOffset = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LOG").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Journal").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Day picker

    private var dayPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.dayOffsets, id: \.self) { off in
                        dayPill(off).id(off)
                    }
                }
                .padding(.horizontal, 1)
            }
            .onAppear { DispatchQueue.main.async { proxy.scrollTo(dayOffset, anchor: .center) } }
        }
    }

    private func dayPill(_ off: Int) -> some View {
        let on = dayOffset == off
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { dayOffset = off }
        } label: {
            Text(dayLabel(off))
                .font(StrandFont.subhead)
                .foregroundStyle(on ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(Capsule().fill(on ? StrandPalette.gold.opacity(0.18) : StrandPalette.surfaceRaised))
                .overlay(Capsule().strokeBorder(on ? StrandPalette.gold.opacity(0.5) : StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func dayLabel(_ offset: Int) -> String {
        switch offset {
        case -1: return "Tomorrow"
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(offset)d ago"
        }
    }

    // MARK: - Mood (real: MoodStore / repo.saveMood / repo.mood)

    private var moodCard: some View {
        StrandCard(tint: StrandPalette.gold) {
            VStack(alignment: .leading, spacing: 12) {
                PremiumSectionHeader(title: "How do you feel?", trailing: dayLabel(dayOffset))
                HStack(spacing: 8) {
                    ForEach(Array(MoodStore.scale), id: \.self) { value in
                        moodFace(value)
                    }
                }
            }
        }
    }

    private func moodFace(_ value: Int) -> some View {
        let selected = selectedMood == value
        return Button {
            selectedMood = value
            Task { await repo.saveMood(day: dayKey, value: value) }
        } label: {
            VStack(spacing: 4) {
                Text(MoodStore.face(for: value)).font(.system(size: 22))
                Text(MoodStore.label(for: value))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? StrandPalette.gold : StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(selected ? StrandPalette.gold.opacity(0.16) : StrandPalette.surfaceInset))
            .overlay(Capsule().strokeBorder(selected ? StrandPalette.gold.opacity(0.6) : StrandPalette.hairline,
                                            lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(MoodStore.label(for: value)), mood \(value) of 5")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A real mood-history bar strip — the fixed 1–5 check-in scale means each bar's height is
    /// directly comparable day to day, no per-week min/max needed. Only renders once there are at
    /// least two logged days; a gap in check-ins simply isn't in the series (never a fabricated bar).
    @ViewBuilder private var moodHistoryCard: some View {
        if moodHistory.count >= 2 {
            StrandCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MOOD · LAST \(moodHistory.count) DAYS").font(StrandFont.overline).tracking(1.3)
                        .foregroundStyle(StrandPalette.textTertiary)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(moodHistory) { p in
                            VStack {
                                Spacer(minLength: 0)
                                Capsule().fill(StrandPalette.gold.opacity(0.35 + 0.65 * (p.value - 1) / 4))
                                    .frame(height: 6 + CGFloat((p.value - 1) / 4) * 26)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: 34)
                }
            }
        }
    }

    // MARK: - Log (real: JournalCatalogStore / repo.saveJournalAnswer / saveJournalNumeric / clearJournalAnswer)

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Log").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button(editing ? "Done" : "Edit") { editing.toggle() }
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.gold)
            }
            StrandCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(editing
                         ? "Rename, regroup, or remove an item to tidy your list. Renaming keeps the original question behind the scenes, so a WHOOP import still lines up. Custom items are deleted; built-in ones are hidden and can be restored below."
                         : dayOffset == -1
                         ? "Logging ahead for tomorrow: today's activities inform tomorrow's recovery, just as yesterday's are reflected in today's."
                         : "Answers are about the night and day leading into this morning, the same attribution a WHOOP export uses, so logged and imported days line up.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(JournalGroup.displayOrder, id: \.self) { group in
                        groupBlock(group)
                    }
                }
            }
        }
    }

    @ViewBuilder private func groupBlock(_ group: JournalGroup) -> some View {
        let groupItems = items(in: group)
        if !groupItems.isEmpty || editing {
            let collapsed = collapsedGroups.contains(group.rawValue)
            VStack(alignment: .leading, spacing: 8) {
                Button { toggleCollapsed(group) } label: {
                    HStack(spacing: 6) {
                        Text(group.title.uppercased())
                            .font(StrandFont.overline)
                            .tracking(StrandFont.overlineTracking)
                            .foregroundStyle(StrandPalette.textTertiary)
                        Text("\(groupItems.count)")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                        Spacer()
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(groupItems.count) items, \(collapsed ? "collapsed" : "expanded")")

                if !collapsed {
                    ForEach(groupItems) { item in itemRow(item) }
                }
            }
        }
    }

    @ViewBuilder private func itemRow(_ item: JournalCatalogItem) -> some View {
        HStack {
            Text(verbatim: item.display)
                .font(StrandFont.body)
                .foregroundStyle(item.hidden ? StrandPalette.textTertiary : StrandPalette.textPrimary)
            Spacer()
            if editing {
                editControls(item)
            } else if item.kind.isNumeric {
                numericField(item)
            } else {
                answerPill("Yes", q: item.canonical, value: true)
                answerPill("No", q: item.canonical, value: false)
            }
        }
    }

    private func answerPill(_ label: String, q: String, value: Bool) -> some View {
        let selected = answers[q] == value
        return Button {
            Task {
                // Tri-state: tapping the already-selected chip clears the answer.
                if selected {
                    await repo.clearJournalAnswer(day: dayKey, question: q)
                } else {
                    await repo.saveJournalAnswer(day: dayKey, question: q, answeredYes: value)
                }
                await loadDay()
            }
        } label: {
            Text(label)
                .font(StrandFont.footnote)
                .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(selected ? StrandPalette.gold : StrandPalette.surfaceInset, in: Capsule())
                .overlay(Capsule().stroke(selected ? StrandPalette.gold : StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Numeric field

    private func numericField(_ item: JournalCatalogItem) -> some View {
        let current = numericAnswers[item.canonical]
        return HStack(spacing: 6) {
            stepperButton("minus", q: item.canonical, current: current)
            PremiumNumericField(value: current, onCommit: { v in commitNumeric(item.canonical, value: v) })
                .frame(width: 56)
            if let unit = item.kind.unitLabel, !unit.isEmpty {
                Text(verbatim: unit).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            stepperButton("plus", q: item.canonical, current: current)
            if current != nil {
                Button {
                    Task { await repo.clearJournalAnswer(day: dayKey, question: item.canonical); await loadDay() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(item.display)")
            }
        }
    }

    private func stepperButton(_ symbol: String, q: String, current: Double?) -> some View {
        Button {
            let base = current ?? 0
            let next = max(0, symbol == "plus" ? base + 1 : base - 1)
            commitNumeric(q, value: next)
        } label: {
            Image(systemName: "\(symbol).circle")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }

    private func commitNumeric(_ q: String, value: Double) {
        Task {
            await repo.saveJournalNumeric(day: dayKey, question: q, value: value)
            await loadDay()
        }
    }

    // MARK: - Edit-mode controls

    private func editControls(_ item: JournalCatalogItem) -> some View {
        HStack(spacing: 10) {
            if item.hidden {
                Button("Restore") { catalog.restore(item.canonical) }
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.gold)
            } else {
                Menu {
                    Button("Rename…") { startRename(item) }
                    Menu("Group") {
                        ForEach(JournalGroup.displayOrder, id: \.self) { g in
                            Button(g.title) { catalog.setGroup(item.canonical, to: g) }
                        }
                    }
                    if item.kind.isNumeric {
                        Button("Change to Yes/No") { catalog.setKind(item.canonical, to: .bool) }
                    } else {
                        Button("Change to Number") { catalog.setKind(item.canonical, to: .numeric(unitLabel: nil)) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                .accessibilityLabel("Edit \(item.display)")

                Button { catalog.remove(item.canonical) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.metricRose)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.custom ? "Delete \(item.display)" : "Hide \(item.display)")
            }
        }
    }

    // MARK: - Rename sheet

    private func startRename(_ item: JournalCatalogItem) {
        renameDraft = item.displayName ?? item.canonical
        renaming = item
    }

    private func renameSheet(_ item: JournalCatalogItem) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename item").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                TextField("Display name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                Text("History stays under the original question so WHOOP imports still line up.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { renaming = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        catalog.rename(item.canonical, to: renameDraft)
                        renaming = nil
                    }
                }
            }
        }
        .presentationDetents([.height(240)])
    }

    // MARK: - Add custom item

    private var addCustomCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                PremiumSectionHeader(title: "Add a custom item")
                HStack(spacing: 8) {
                    TextField("e.g. Did you stretch?", text: $customDraft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(StrandPalette.surfaceInset))
                        .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
                    Button(customIsNumeric ? "Number" : "Yes/No") { customIsNumeric.toggle() }
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Capsule().fill(StrandPalette.surfaceInset))
                        .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
                }
                HStack {
                    Picker("Group", selection: $customGroup) {
                        ForEach(JournalGroup.displayOrder, id: \.self) { g in Text(g.title).tag(g) }
                    }
                    .pickerStyle(.menu)
                    .tint(StrandPalette.textSecondary)
                    Spacer()
                    Button("Add") {
                        let t = customDraft.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        catalog.addCustom(t, kind: customIsNumeric ? .numeric(unitLabel: nil) : .bool,
                                          group: customGroup)
                        customDraft = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.gold)
                    .disabled(customDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Load

    /// Imported question strings (so logged days join imported history) — reloaded whenever the
    /// repo's data changes; the selected day's answers/numeric/mood are loaded separately below.
    private func load() async {
        let imported = await repo.importedJournalEntries()
        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        let history = await repo.moodSeries(days: 14)
        await MainActor.run {
            self.importedQuestions = importedQs
            self.moodHistory = history.map { MoodPoint(day: $0.day, value: $0.value) }
        }
        await loadDay()
    }

    /// The selected day's native answers, numeric values, and mood — reloaded on every day-picker
    /// change and after every write.
    private func loadDay() async {
        let key = dayKey
        async let a = repo.nativeJournalAnswers(day: key)
        async let n = repo.nativeJournalNumeric(day: key)
        async let m = repo.mood(day: key)
        let (aa, nn, mm) = await (a, n, m)
        await MainActor.run {
            self.answers = aa
            self.numericAnswers = nn
            self.selectedMood = mm
        }
    }
}

/// A compact numeric log field: shows the current value or a ghost placeholder, commits a Double on
/// return / focus-out. Premium-styled twin of `JournalLogCard`'s private `NumericLogField`.
private struct PremiumNumericField: View {
    let value: Double?
    let onCommit: (Double) -> Void

    @State private var text = ""

    var body: some View {
        TextField("—", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(StrandPalette.textPrimary)
            .padding(.vertical, 6)
            .background(Capsule().fill(StrandPalette.surfaceInset))
            .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
            .onAppear { text = value.map(Self.format) ?? "" }
            .onChange(of: value) { _, v in text = v.map(Self.format) ?? "" }
            .onSubmit { commit() }
            .keyboardType(.decimalPad)
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned) { onCommit(v) }
    }

    private static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
#endif
