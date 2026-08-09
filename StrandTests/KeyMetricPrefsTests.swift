import XCTest
@testable import Strand

/// Pins the Key-Metrics layout persistence (#251): the CONTRACT is that a customisation (add a tile, remove
/// a tile, reorder tiles) survives relaunch — a fresh decode of exactly what was last encoded, nothing
/// silently reverting to the default set. Twin of the Android `KeyMetricPrefsTest`, same "today.keyMetrics"
/// key, same comma-joined encoding, same "unknown/all-unknown decodes to the default order, never to an
/// empty grid" rule.
final class KeyMetricPrefsTests: XCTestCase {

    func testEmptyOrUnsetYieldsFullDefaultOrder() {
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled(""), KeyMetric.defaultOrder)
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled("   "), KeyMetric.defaultOrder)
    }

    /// "Add a metric": start from a saved subset, encode it back with one more tile appended, and decode —
    /// the newly-added tile must be present, in the position it was added, with everything else untouched.
    func testAddingAMetricIsReflectedOnNextDecode() {
        let before = KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode([.charge, .hrv]))
        XCTAssertEqual(before, [.charge, .hrv])

        let after = KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode(before + [.steps]))
        XCTAssertEqual(after, [.charge, .hrv, .steps])
    }

    /// "Remove a metric": a tile dropped from the enabled list before encoding must not reappear on decode
    /// — it degrades to hidden, not to "still shown from some other default".
    func testRemovingAMetricIsReflectedOnNextDecode() {
        let full: [KeyMetric] = [.charge, .effort, .rest, .hrv, .steps]
        let withoutEffort = full.filter { $0 != .effort }
        let decoded = KeyMetricPrefs.decodeEnabled(KeyMetricPrefs.encode(withoutEffort))
        XCTAssertEqual(decoded, [.charge, .rest, .hrv, .steps])
        XCTAssertFalse(decoded.contains(.effort))
    }

    /// "Reorder metrics": the saved ORDER, not just the saved SET, must round-trip exactly.
    func testReorderingMetricsIsReflectedOnNextDecode() {
        let reordered: [KeyMetric] = [.rest, .charge, .weight, .effort, .hrv]
        let encoded = KeyMetricPrefs.encode(reordered)
        XCTAssertEqual(encoded, "rest,charge,weight,effort,hrv")
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled(encoded), reordered)
    }

    /// "Relaunch": decoding is a pure function of the persisted string, so re-decoding the SAME stored
    /// string (as a cold launch would) must yield byte-identical results, independent of how many times it's
    /// been decoded already — no hidden mutable state drifts the answer between calls.
    func testRepeatedDecodeOfTheSameStoredStringIsStable() {
        let encoded = KeyMetricPrefs.encode([.calories, .bloodOxygen, .charge])
        let first = KeyMetricPrefs.decodeEnabled(encoded)
        let second = KeyMetricPrefs.decodeEnabled(encoded)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, [.calories, .bloodOxygen, .charge])
    }

    func testDropsUnknownTokensAndCollapsesDuplicates() {
        let messy = "charge,BOGUS,charge,hrv, ,hrv,steps"
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled(messy), [.charge, .hrv, .steps])
    }

    /// The bug this test would have caught: a saved string that decodes to NO known tile (every token
    /// stale/unrecognised) must fall back to the full default order — matching `DashboardCardPrefs` and the
    /// Android twin — never to an empty grid, which reads exactly like the user's customisation vanished.
    func testAllUnknownTokensFallBackToDefaultOrderNotAnEmptyGrid() {
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled("nope,zzz,BOGUS"), KeyMetric.defaultOrder)
        XCTAssertFalse(KeyMetricPrefs.decodeEnabled("nope,zzz,BOGUS").isEmpty)
    }

    func testDefaultOrderCoversEveryCase() {
        XCTAssertEqual(Set(KeyMetric.defaultOrder), Set(KeyMetric.allCases))
        XCTAssertEqual(KeyMetric.defaultOrder.count, KeyMetric.allCases.count)
    }

    func testMetricRawKeysAreStableAndUnique() {
        let raws = KeyMetric.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "raw keys must be unique (they're the persisted identity)")
        // Pin the exact wire strings — they must match the Android KeyMetric byte-for-byte.
        XCTAssertEqual(
            raws,
            ["charge", "effort", "rest", "hrv", "restingHr", "bloodOxygen", "respiratory", "steps", "weight", "calories"]
        )
    }

    /// End-to-end persistence through a throwaway UserDefaults suite, exactly as `@AppStorage(KeyMetricPrefs.
    /// layoutKey)` would read/write it — pins the key name itself, not just the pure encode/decode functions.
    func testCustomisationPersistsThroughUserDefaults() {
        let suite = "KeyMetricPrefsTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Fresh install: nothing written yet, reads as the full default order.
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled(defaults.string(forKey: KeyMetricPrefs.layoutKey) ?? ""),
                       KeyMetric.defaultOrder)

        // User customises: keeps only Charge + Rest, reordered.
        defaults.set(KeyMetricPrefs.encode([.rest, .charge]), forKey: KeyMetricPrefs.layoutKey)

        // "Relaunch": a brand-new UserDefaults handle onto the SAME suite reads the persisted choice back.
        let relaunched = UserDefaults(suiteName: suite)!
        XCTAssertEqual(KeyMetricPrefs.decodeEnabled(relaunched.string(forKey: KeyMetricPrefs.layoutKey) ?? ""),
                       [.rest, .charge])

        defaults.removePersistentDomain(forName: suite)
    }
}
