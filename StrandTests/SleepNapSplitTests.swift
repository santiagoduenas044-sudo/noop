import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

/// Pins the nap/main-night split that the iOS Sleep tab's Naps card depends on.
///
/// The card lists "every block on the day OUTSIDE the bridged main-night group" — the same rule the
/// classic macOS naps card uses. Two ways that can go wrong, and both have historically:
///   * a real afternoon nap gets folded into the night (#518), which would mislabel the awake daytime
///     gap as sleep and inflate the night's total; or
///   * a briefly-interrupted night's bridged fragments get treated as naps (#555), so one night
///     renders as a night plus phantom naps.
///
/// `PremiumSleepIntel.latestDayNaps` is `#if os(iOS)` and cannot be tested from this macOS-only
/// bundle, so the contract is pinned here at the shared selector it is built from
/// (`SleepView.mainNightGroup`) — which is the thing that would actually break.
final class SleepNapSplitTests: XCTestCase {

    /// Local-calendar timestamps: `mainNightGroup` scores against `TimeZone.current`, so a test built
    /// from fixed unix constants would pass or fail depending on the runner's zone. Building from the
    /// local calendar keeps it correct everywhere.
    private func ts(daysFromToday: Int, hour: Int, minute: Int = 0) -> Int {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: daysFromToday, to: cal.startOfDay(for: Date()))!
        return Int(cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
            .timeIntervalSince1970)
    }

    private func session(_ start: Int, _ end: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil,
                           avgHrv: nil, stagesJSON: nil)
    }

    /// The naps-card rule, stated directly: blocks outside the bridged group.
    private func naps(_ blocks: [CachedSleepSession]) -> [CachedSleepSession] {
        let groupStarts = Set(SleepView.mainNightGroup(blocks).map { $0.startTs })
        return blocks.filter { !groupStarts.contains($0.startTs) }
            .sorted { $0.effectiveStartTs < $1.effectiveStartTs }
    }

    /// An afternoon nap must stay a nap — never bridged into the night, whose gap to it is many hours.
    func testAfternoonNapIsNotFoldedIntoTheNight() {
        let night = session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 7))
        let nap = session(ts(daysFromToday: 0, hour: 14), ts(daysFromToday: 0, hour: 14, minute: 40))
        let split = naps([night, nap])
        XCTAssertEqual(split.count, 1, "the day has exactly one nap")
        XCTAssertEqual(split.first?.startTs, nap.startTs)
        XCTAssertEqual(SleepView.mainNightGroup([night, nap]).map(\.startTs), [night.startTs],
                       "the main-night group must be the night alone")
    }

    /// A night split by a brief wake is ONE night: both fragments belong to the group, so the naps
    /// list is empty. The gap here is 20 minutes, well inside `gapBridgeMaxMin` (60).
    func testBridgedNightFragmentsAreNotNaps() {
        let first = session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 2))
        let second = session(ts(daysFromToday: 0, hour: 2, minute: 20), ts(daysFromToday: 0, hour: 7))
        XCTAssertTrue(naps([first, second]).isEmpty,
                      "a briefly-interrupted night must not render as phantom naps")
        XCTAssertEqual(Set(SleepView.mainNightGroup([first, second]).map(\.startTs)),
                       [first.startTs, second.startTs])
    }

    /// Both at once — the realistic day: an interrupted night AND a genuine nap. Exactly the nap is
    /// listed, and the night keeps both of its fragments.
    func testInterruptedNightPlusRealNapSplitsCorrectly() {
        let first = session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 2))
        let second = session(ts(daysFromToday: 0, hour: 2, minute: 20), ts(daysFromToday: 0, hour: 7))
        let nap = session(ts(daysFromToday: 0, hour: 15), ts(daysFromToday: 0, hour: 15, minute: 30))
        let split = naps([first, second, nap])
        XCTAssertEqual(split.map(\.startTs), [nap.startTs])
        XCTAssertEqual(Set(SleepView.mainNightGroup([first, second, nap]).map(\.startTs)),
                       [first.startTs, second.startTs])
    }

    /// The invariant the card cannot violate: the block chosen as the day's MAIN sleep must never
    /// also appear in the naps list. The Sleep screen renders both from the same day's blocks, so if
    /// these two disagree the same sleep is shown twice and counted twice in the Main/Naps/Total row.
    /// Asserted across several day shapes, including a day whose only block is a daytime sleep.
    func testTheMainBlockIsNeverAlsoListedAsANap() {
        let days: [[CachedSleepSession]] = [
            // A single daytime block — the only thing there is to pick as "main".
            [session(ts(daysFromToday: 0, hour: 13), ts(daysFromToday: 0, hour: 14))],
            // A normal night.
            [session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 7))],
            // Night + nap.
            [session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 7)),
             session(ts(daysFromToday: 0, hour: 14), ts(daysFromToday: 0, hour: 14, minute: 40))],
            // Interrupted night + two naps.
            [session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 2)),
             session(ts(daysFromToday: 0, hour: 2, minute: 20), ts(daysFromToday: 0, hour: 7)),
             session(ts(daysFromToday: 0, hour: 12), ts(daysFromToday: 0, hour: 12, minute: 25)),
             session(ts(daysFromToday: 0, hour: 17), ts(daysFromToday: 0, hour: 17, minute: 30))],
        ]
        for blocks in days {
            guard let main = SleepView.mainNightSession(blocks) else {
                return XCTFail("a non-empty day must always resolve a main block")
            }
            XCTAssertFalse(naps(blocks).contains { $0.startTs == main.startTs },
                           "the main block appeared in the naps list for a \(blocks.count)-block day")
        }
    }

    /// A hand-added nap carries `startTsAdjusted` once its onset is corrected. The split must key on
    /// the immutable detected `startTs` (what the group returns), while the DISPLAYED order uses the
    /// effective onset — conflating the two is what spawns duplicate rows.
    func testSplitKeysOnDetectedStartWhileOrderingByEffectiveOnset() {
        let night = session(ts(daysFromToday: -1, hour: 23), ts(daysFromToday: 0, hour: 7))
        let later = CachedSleepSession(startTs: ts(daysFromToday: 0, hour: 16),
                                       endTs: ts(daysFromToday: 0, hour: 16, minute: 40),
                                       efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil,
                                       userEdited: true,
                                       startTsAdjusted: ts(daysFromToday: 0, hour: 15, minute: 50))
        let earlier = session(ts(daysFromToday: 0, hour: 12), ts(daysFromToday: 0, hour: 12, minute: 30))
        let split = naps([night, later, earlier])
        XCTAssertEqual(split.map(\.startTs), [earlier.startTs, later.startTs],
                       "naps order by effective onset, and the corrected nap is still matched by its detected key")
        XCTAssertEqual(split.last?.effectiveStartTs, ts(daysFromToday: 0, hour: 15, minute: 50))
    }
}
