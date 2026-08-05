import XCTest
@testable import StrandAnalytics

/// Pins the "Add a nap" seed window.
///
/// The failure this guards is silent: `clampedEditWindow` refuses a window lying entirely in the
/// future, so a picker seeded ahead of the clock opens fine, accepts the user's taps, and then saves
/// NOTHING. The seed must therefore always land in the past, at every time of day, whether or not the
/// day has a recorded night behind it.
final class NapSeedWindowTests: XCTestCase {

    /// 2026-08-05 15:00 UTC, as a stable "now".
    private let now = 1_785_078_000

    /// The invariant that makes the seed savable at all: it is a real, already-elapsed window.
    func testSeedIsAlwaysAPastNonEmptyWindow() {
        // Sweep a whole day's worth of possible wake times, including ones in the future.
        for offset in stride(from: -24 * 3600, through: 6 * 3600, by: 900) {
            let seed = SleepEditGuard.napSeedWindow(lastWakeTs: now + offset, now: now)
            XCTAssertLessThan(seed.start, seed.end, "wake offset \(offset): empty window")
            XCTAssertLessThanOrEqual(seed.end, now, "wake offset \(offset): seed ends in the future")
            XCTAssertNotNil(SleepEditGuard.clampedEditWindow(start: seed.start, end: seed.end, now: now),
                            "wake offset \(offset): seed is refused by the persistence guard")
        }
    }

    /// No night recorded yet (a first-run user, or a day whose sync hasn't landed) must still get a
    /// usable seed rather than nothing — this is exactly the user who most needs to log by hand.
    func testSeedWithNoRecordedNight() {
        let seed = SleepEditGuard.napSeedWindow(lastWakeTs: nil, now: now)
        XCTAssertEqual(seed.end, now)
        XCTAssertEqual(seed.end - seed.start, SleepEditGuard.napSeedDurationSec)
        XCTAssertNotNil(SleepEditGuard.clampedEditWindow(start: seed.start, end: seed.end, now: now))
    }

    /// Well after a morning wake, the seed uses the wake+1h anchor — the natural place to look for a
    /// missed daytime nap.
    func testSeedAnchorsAfterWakeOnceThatWindowHasElapsed() {
        let wake = now - 6 * 3600
        let seed = SleepEditGuard.napSeedWindow(lastWakeTs: wake, now: now)
        XCTAssertEqual(seed.start, wake + SleepEditGuard.napSeedAfterWakeSec)
        XCTAssertEqual(seed.end - seed.start, SleepEditGuard.napSeedDurationSec)
    }

    /// Right after a morning sync the wake+1h window has NOT elapsed, so the anchor would be in the
    /// future — the case that produced a picker whose save did nothing. It must fall back instead.
    func testSeedFallsBackWhenTheWakeAnchorHasNotElapsed() {
        let wake = now - 10 * 60           // woke ten minutes ago
        let seed = SleepEditGuard.napSeedWindow(lastWakeTs: wake, now: now)
        XCTAssertEqual(seed.end, now, "must fall back to the half-hour that just ended")
        XCTAssertLessThan(seed.start, now)
    }

    /// A stale night (unsynced strap: the newest recorded night is a day or more old) must not drop the
    /// picker into the middle of a past day.
    func testStaleWakeIsNotUsedAsTheAnchor() {
        let stale = now - (SleepEditGuard.napSeedMaxWakeAgeSec + 3600)
        let seed = SleepEditGuard.napSeedWindow(lastWakeTs: stale, now: now)
        XCTAssertEqual(seed.end, now)
        XCTAssertEqual(seed.start, now - SleepEditGuard.napSeedDurationSec)
    }

    /// Exact boundary: the anchor is used the instant its full window has elapsed, and not before.
    func testSeedBoundaryAtExactlyElapsed() {
        let span = SleepEditGuard.napSeedAfterWakeSec + SleepEditGuard.napSeedDurationSec
        let elapsed = SleepEditGuard.napSeedWindow(lastWakeTs: now - span, now: now)
        XCTAssertEqual(elapsed.start, now - span + SleepEditGuard.napSeedAfterWakeSec)
        XCTAssertEqual(elapsed.end, now)

        let oneShort = SleepEditGuard.napSeedWindow(lastWakeTs: now - span + 1, now: now)
        XCTAssertEqual(oneShort.end, now)
        XCTAssertEqual(oneShort.start, now - SleepEditGuard.napSeedDurationSec)
    }
}
