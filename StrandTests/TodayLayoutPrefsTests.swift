import XCTest
@testable import Strand

/// Twin of the Android `TodayLayoutPrefsTest` (#today-layout): default order, encode/decode round-trip,
/// reorder, and the never-hide "insert missing section at its default position" invariant — pinned on both
/// platforms so the byte-identical "today.sectionOrder" wire format can't drift.
final class TodayLayoutPrefsTests: XCTestCase {

    func testEmptyOrUnsetYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(""), TodaySection.defaultOrder)
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("   "), TodaySection.defaultOrder)
    }

    func testEncodeDecodeRoundTripsAReorderedList() {
        let reordered: [TodaySection] = [
            .heartRate, .hero, .yourCards, .liveSession, .synthesis, .intelligence, .keyMetrics, .workouts,
            .recoveryVitals, .journal,
        ]
        let encoded = TodayLayoutPrefs.encode(reordered)
        XCTAssertEqual(encoded, "heartRate,hero,yourCards,liveSession,synthesis,intelligence,keyMetrics,workouts,recoveryVitals,journal")
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder(encoded), reordered)
    }

    /// The v1 upgrade path: an order saved by the FIRST cut (6 sections — no hero/liveSession, which were
    /// pinned then) must surface the newer sections at their default position, not teleport them to the
    /// bottom of the user's saved order. The iOS-only intelligence block lands just after synthesis.
    func testSavedOrderFromFirstCutInsertsHeroAndSessionAtTheirDefaultPosition() {
        let firstCut = "synthesis,keyMetrics,workouts,heartRate,recoveryVitals,yourCards"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(firstCut),
            // journal(9) follows everything saved → appended; intelligence(3) lands right after synthesis.
            [.hero, .liveSession, .synthesis, .intelligence, .keyMetrics, .workouts, .heartRate, .recoveryVitals, .yourCards, .journal]
        )
    }

    func testInsertsAnyMissingSectionAtItsDefaultPositionRelativeToSaved() {
        let partial = "heartRate,synthesis,keyMetrics,recoveryVitals"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(partial),
            [.hero, .liveSession, .intelligence, .workouts, .heartRate, .synthesis, .keyMetrics, .recoveryVitals, .yourCards, .journal]
        )
    }

    func testDropsUnknownTokensAndCollapsesDuplicates() {
        let messy = "yourCards,BOGUS,yourCards,heartRate, ,heartRate"
        XCTAssertEqual(
            TodayLayoutPrefs.decodeOrder(messy),
            [.hero, .liveSession, .synthesis, .intelligence, .keyMetrics, .workouts, .recoveryVitals, .yourCards, .heartRate, .journal]
        )
    }

    func testAllJunkYieldsDefaultOrder() {
        XCTAssertEqual(TodayLayoutPrefs.decodeOrder("nope,,zzz"), TodaySection.defaultOrder)
    }

    /// defaultOrder must cover EVERY case: the never-hide merge iterates it, so a case missing from the
    /// default order could otherwise be dropped from render (Android) or mis-sorted (iOS).
    func testDefaultOrderCoversEveryCase() {
        XCTAssertEqual(Set(TodaySection.defaultOrder), Set(TodaySection.allCases))
        XCTAssertEqual(TodaySection.defaultOrder.count, TodaySection.allCases.count)
    }

    func testSectionRawKeysAreStableAndUnique() {
        let raws = TodaySection.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "raw keys must be unique (they're the persisted identity)")
        // Pin the exact wire strings. Every key here EXCEPT `intelligence` must match the Android
        // TodaySection byte-for-byte; `intelligence` is an iPhone-only narrative block the Android twin does
        // not yet reimplement, and its decoder ignores the unknown token, so the wire format stays
        // cross-compatible (an iOS order restored on Android drops it; an Android order restored on iOS
        // re-inserts it at its default position).
        XCTAssertEqual(
            raws,
            ["hero", "liveSession", "synthesis", "intelligence", "keyMetrics", "workouts", "heartRate", "recoveryVitals", "yourCards", "journal"]
        )
    }
}
