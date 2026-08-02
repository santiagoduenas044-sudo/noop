#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Edit Home — the dashboard customiser.
///
/// Lets the user pick which of the catalog's metrics appear on Home, reorder them, and switch the
/// grid between compact (value only) and expanded (value plus trend). This is what turns Home from
/// a fixed six-card screen into "a simple dashboard OR an advanced health dashboard depending on
/// preference".
///
/// Metrics the device has never recorded are still listed, but clearly marked unavailable and not
/// selectable — the honest alternative to hiding them (the user can see the app supports them) or
/// to letting them be added and render empty.
struct PremiumEditHomeView: View {
    @ObservedObject var layout: PremiumHomeLayoutStore
    @EnvironmentObject var repo: Repository

    /// Availability is resolved once per appearance rather than per row, so scrolling a 24-row list
    /// doesn't re-scan the whole history for every cell.
    @State private var available: Set<PremiumMetricID> = []

    var body: some View {
        List {
            presentationSection
            ForEach(PremiumMetricGroup.allCases, id: \.self) { group in
                groupSection(group)
            }
            resetSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .task(id: repo.refreshSeq) { resolveAvailability() }
    }

    private func resolveAvailability() {
        var found: Set<PremiumMetricID> = []
        for def in PremiumMetricCatalog.all {
            if PremiumMetricCatalog.isAvailable(def.id, repo: repo) { found.insert(def.id) }
        }
        available = found
    }

    // MARK: Presentation

    private var presentationSection: some View {
        Section {
            Toggle(isOn: $layout.compact) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compact cards").foregroundStyle(StrandPalette.textPrimary)
                    Text("Hide the mini trend line to fit more on screen")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .tint(StrandPalette.accent)
        } header: {
            Text("Presentation")
        } footer: {
            Text("\(layout.visible.count) metric\(layout.visible.count == 1 ? "" : "s") shown on Home.")
        }
        .listRowBackground(StrandPalette.surfaceRaised)
    }

    // MARK: Metric groups

    @ViewBuilder private func groupSection(_ group: PremiumMetricGroup) -> some View {
        let defs: [PremiumMetricDef] = PremiumMetricCatalog.all.filter { $0.group == group }
        if !defs.isEmpty {
            Section {
                ForEach(defs) { def in
                    metricRow(def)
                }
            } header: {
                Text(group.rawValue)
            }
            .listRowBackground(StrandPalette.surfaceRaised)
        }
    }

    private func metricRow(_ def: PremiumMetricDef) -> some View {
        let isAvailable: Bool = available.contains(def.id)
        let isShown: Bool = !layout.hidden.contains(def.id)
        return HStack(spacing: 12) {
            PremiumIconTile(system: def.icon, tint: isAvailable ? def.tint : StrandPalette.textTertiary,
                            size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(def.name)
                    .font(StrandFont.body)
                    .foregroundStyle(isAvailable ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                Text(isAvailable ? def.provenance.label : "No readings recorded yet")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 8)
            if isShown && isAvailable {
                reorderControls(def.id)
            }
            Button {
                layout.toggle(def.id)
            } label: {
                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isShown ? StrandPalette.accent : StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : 0.4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(def.name), \(isShown ? "shown" : "hidden")\(isAvailable ? "" : ", unavailable")")
    }

    /// Up/down nudges. A plain two-button pair rather than drag-to-reorder, because the list is
    /// grouped by category — a drag across group boundaries would have no meaningful destination.
    private func reorderControls(_ id: PremiumMetricID) -> some View {
        let idx: Int = layout.order.firstIndex(of: id) ?? 0
        let isFirst: Bool = idx == 0
        let isLast: Bool = idx == layout.order.count - 1
        return HStack(spacing: 2) {
            Button { layout.move(id, by: -1) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isFirst ? StrandPalette.textTertiary.opacity(0.4) : StrandPalette.textSecondary)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain).disabled(isFirst)
            Button { layout.move(id, by: 1) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isLast ? StrandPalette.textTertiary.opacity(0.4) : StrandPalette.textSecondary)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain).disabled(isLast)
        }
        .accessibilityHidden(true)
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                layout.resetToDefaults()
            } label: {
                Text("Reset to defaults")
            }
        } footer: {
            Text("Restores the original six cards and the expanded layout.")
        }
        .listRowBackground(StrandPalette.surfaceRaised)
    }
}
#endif
