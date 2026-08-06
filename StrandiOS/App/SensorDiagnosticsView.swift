#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Developer → Sensor Diagnostics — the live instrument that answers "the app SHOWS live HR 55, so why
/// is today's HR history empty?" and its siblings for every stream. It deliberately puts two numbers side
/// by side for each sensor: the LIVE session counters (what the radio is receiving right now, from
/// `LiveState`) and the PERSISTED counts (what actually landed on disk, from `WhoopStore.streamPersistCounts`).
/// When those disagree — live HR flowing but 0 persisted today — the gap IS the bug, and this screen makes it
/// visible without a strap-log export.
///
/// Read-only and additive: it never writes to the store or the live state, so it cannot itself perturb the
/// data path it is diagnosing. Honest by construction — every "unavailable" reason is derived from the real
/// counts + connection state, never asserted. No fabricated values.
struct SensorDiagnosticsView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState

    @State private var today: WhoopStore.StreamPersistCounts?
    @State private var allTime: WhoopStore.StreamPersistCounts?
    @State private var storage: (decodedRows: Int, rawBatches: Int, rawBytes: Int)?
    @State private var deviceId = "—"
    @State private var dayStartUnix = 0
    @State private var loaded = false

    /// One row's health, derived purely from the counts + live connection — never asserted.
    private enum Health { case ok, stale, never }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                connectionCard
                writeHealthCard
                streamsCard
                if let s = storage { storageCard(s) }
                footnote
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
        }
        .background(PremiumAmbient(tints: [StrandPalette.gold]).ignoresSafeArea())
        .navigationTitle("Sensor Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Load (read-only)

    private func load() async {
        let now = Int(Date().timeIntervalSince1970)
        // "Today" = the logical day (rolls at 04:00 local, #144) — the SAME anchor the Today screens use,
        // so an empty "today" here matches an empty "today" there rather than a different midnight.
        let start = Int(Repository.logicalDayStart(Date()).timeIntervalSince1970)
        dayStartUnix = start
        deviceId = repo.deviceId
        guard let store = await repo.storeHandle() else {
            loaded = true
            return
        }
        let dev = repo.deviceId
        today = try? await store.streamPersistCounts(deviceId: dev, from: start, to: now)
        allTime = try? await store.streamPersistCounts(deviceId: dev, from: 0, to: now)
        storage = try? await store.storageStats()
        loaded = true
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEVELOPER").font(StrandFont.overline).tracking(1.4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Sensor Diagnostics").font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            Text("Live radio vs. what actually persisted. Pull to refresh.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Connection

    private var connectionCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("CONNECTION")
                kv("State", live.connectionStatusLabel,
                   tint: live.connected ? StrandPalette.recovery : StrandPalette.textTertiary)
                kv("Bond", bondLabel)
                kv("Worn", live.worn ? "on wrist" : "off wrist")
                kv("Live HR", live.heartRate.map { "\($0) bpm" } ?? "—",
                   tint: (live.heartRate ?? 0) > 0 ? StrandPalette.recovery : StrandPalette.textTertiary)
                kv("Last frame", agoLabel(live.lastFrameAtUnix))
                kv("Device id", deviceId)
                strapClockRow
                if live.backfilling { kv("History sync", "running · \(live.syncChunksThisSession) chunks") }
                if let e = live.lastSyncError { kv("Sync error", e, tint: StrandPalette.recovery000) }
                if live.historySyncExperimental {
                    kv("History", "5.0/MG: streams live, offload experimental", tint: StrandPalette.signalYellow)
                }
            }
        }
    }

    private var bondLabel: String {
        if live.encryptedBond { return "encrypted (full)" }
        if live.bonded { return "live-HR only (unbonded)" }
        return "none"
    }

    /// Strap RTC health — the #67 cause. A stale/future strap clock misdates offloaded records, so last
    /// night lands on the wrong day: it IS the "no sleep / empty today / morning strain" cluster. Read from
    /// the persisted newest-record ts (`LiveState.setStrapRange` writes it) — never fabricated.
    private var strapClockRow: some View {
        let newest = UserDefaults.standard.object(forKey: "strap.newestRecordTs") as? Int ?? 0
        if newest <= 0 { return kv("Strap clock", "unknown (no offload yet)") }
        let behind = Int(Date().timeIntervalSince1970) - newest
        if behind > 3 * 86400 {
            return kv("Strap clock", "\(behind / 86400)d BEHIND — records misdated (#67)", tint: StrandPalette.recovery000)
        } else if behind < -3 * 86400 {
            return kv("Strap clock", "\(-behind / 86400)d AHEAD — records misdated (#67)", tint: StrandPalette.recovery000)
        }
        return kv("Strap clock", "OK", tint: StrandPalette.recovery)
    }

    // MARK: - Write health

    private var writeHealthCard: some View {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let okAt = d.double(forKey: "sync.lastWriteOkAt")
        let stalledAt = d.double(forKey: "sync.lastWriteStalledAt")
        let syncedAt = d.double(forKey: "lastSyncedAt")
        return StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("PERSISTENCE")
                kv("Rows last landed", okAt > 0 ? relTime(now - okAt) : "never",
                   tint: okAt > 0 ? StrandPalette.recovery : StrandPalette.signalYellow)
                if stalledAt > 0 && stalledAt >= okAt {
                    kv("⚠ Write stalled", relTime(now - stalledAt) + " — history NOT persisting",
                       tint: StrandPalette.recovery000)
                }
                kv("Last sync", syncedAt > 0 ? relTime(now - syncedAt) : "never")
            }
        }
    }

    // MARK: - Streams

    private var streamsCard: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 0) {
                cardTitle("STREAMS · persisted today / all-time")
                    .padding(.bottom, 6)
                if !loaded {
                    Text("Loading…").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .padding(.vertical, 8)
                } else {
                    streamRow("Heart rate", \.hr)
                    streamRow("HR (PPG-derived)", \.ppgHr)
                    streamRow("R-R intervals", \.rr)
                    streamRow("SpO₂", \.spo2)
                    streamRow("Skin temp", \.skinTemp)
                    streamRow("Respiratory", \.resp)
                    streamRow("Motion (gravity)", \.gravity)
                    streamRow("Steps", \.steps)
                    streamRow("Battery", \.battery)
                    streamRow("Events", \.events)
                }
            }
        }
    }

    @ViewBuilder
    private func streamRow(_ name: String, _ key: KeyPath<WhoopStore.StreamPersistCounts, Int>) -> some View {
        let t = today?[keyPath: key] ?? 0
        let a = allTime?[keyPath: key] ?? 0
        let health: Health = t > 0 ? .ok : (a > 0 ? .stale : .never)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Circle().fill(healthTint(health)).frame(width: 8, height: 8)
                Text(name).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text("\(t) / \(a)").font(StrandFont.bodyNumber)
                    .foregroundStyle(t > 0 ? StrandPalette.textPrimary : StrandPalette.textTertiary)
            }
            if let reason = reason(for: health, allTime: a) {
                Text(reason).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
        }
    }

    /// The honest "why is this unavailable" line — derived from counts + live connection, never asserted.
    private func reason(for health: Health, allTime: Int) -> String? {
        switch health {
        case .ok: return nil
        case .stale:
            return live.connected
                ? "none today yet — connected, but no rows decoded/persisted for today"
                : "none today — strap not connected today (older data on disk)"
        case .never:
            return live.connected
                ? "no rows ever — not transmitted by this strap, or not decoded"
                : "no rows ever — connect + let a history sync run, then refresh"
        }
    }

    // MARK: - Storage

    private func storageCard(_ s: (decodedRows: Int, rawBatches: Int, rawBytes: Int)) -> some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 10) {
                cardTitle("STORAGE")
                kv("Decoded rows (all devices)", "\(s.decodedRows)")
                kv("Raw batches", "\(s.rawBatches)")
                kv("Raw bytes", ByteCountFormatter.string(fromByteCount: Int64(s.rawBytes), countStyle: .file))
            }
        }
    }

    private var footnote: some View {
        Text("“today” counts persisted rows since the logical-day start (04:00 local). A stream that reads "
            + "live above but 0 today points at the persist path or a misdated strap clock, not the radio.")
            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            .padding(.horizontal, 4)
    }

    // MARK: - Small helpers

    private func cardTitle(_ s: String) -> some View {
        Text(s).font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
    }

    private func kv(_ k: String, _ v: String, tint: Color = StrandPalette.textPrimary) -> some View {
        HStack(spacing: 8) {
            Text(k).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 8)
            Text(v).font(StrandFont.footnote).foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }

    private func healthTint(_ h: Health) -> Color {
        switch h {
        case .ok:    return StrandPalette.recovery
        case .stale: return StrandPalette.signalYellow
        case .never: return StrandPalette.textTertiary
        }
    }

    private func agoLabel(_ unix: Int?) -> String {
        guard let unix, unix > 0 else { return "—" }
        return relTime(Date().timeIntervalSince1970 - Double(unix))
    }

    private func relTime(_ deltaSec: Double) -> String {
        if deltaSec < 0 { return "just now" }
        if deltaSec < 60 { return "\(Int(deltaSec))s ago" }
        let min = Int(deltaSec / 60)
        switch true {
        case min < 60:   return "\(min)m ago"
        case min < 1440: return "\(min / 60)h \(min % 60)m ago"
        default:         return "\(min / 1440)d ago"
        }
    }
}
#endif
