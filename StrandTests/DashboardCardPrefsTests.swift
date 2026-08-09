import XCTest
@testable import Strand

/// Pins the "Your cards" dashboard persistence (WHOOP "My Dashboard"): the CONTRACT is that a customisation
/// (add a card, remove a card, reorder cards) survives relaunch. Twin of the Android `DashboardCardPrefsTest`,
/// same "today.dashboardCards" key, same JSON-array encoding, same "unknown/all-unknown decodes to the
/// default selection, never to an empty dashboard" rule.
final class DashboardCardPrefsTests: XCTestCase {

    func testEmptyOrUnsetYieldsDefaultSelection() {
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(""), DashboardCard.defaultSelection)
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled("   "), DashboardCard.defaultSelection)
    }

    /// "Add a card": start from a saved subset, encode it back with one more card appended, and decode —
    /// the newly-added card must be present, in the position it was added, with everything else untouched.
    func testAddingACardIsReflectedOnNextDecode() {
        let before = DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode([.stress, .hrv]))
        XCTAssertEqual(before, [.stress, .hrv])

        let after = DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode(before + [.hydration]))
        XCTAssertEqual(after, [.stress, .hrv, .hydration])
    }

    /// "Remove a card": a card dropped before encoding must not reappear on decode.
    func testRemovingACardIsReflectedOnNextDecode() {
        let full: [DashboardCard] = [.stress, .fitnessAge, .vitality, .hrv, .restingHr]
        let withoutVitality = full.filter { $0 != .vitality }
        let decoded = DashboardCardPrefs.decodeEnabled(DashboardCardPrefs.encode(withoutVitality))
        XCTAssertEqual(decoded, [.stress, .fitnessAge, .hrv, .restingHr])
        XCTAssertFalse(decoded.contains(.vitality))
    }

    /// "Reorder cards": the saved ORDER, not just the saved SET, must round-trip exactly.
    func testReorderingCardsIsReflectedOnNextDecode() {
        let reordered: [DashboardCard] = [.vitality, .stress, .coupled, .hrv]
        let encoded = DashboardCardPrefs.encode(reordered)
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(encoded), reordered)
    }

    /// "Relaunch": decoding is a pure function of the persisted string, so re-decoding the SAME stored
    /// string (as a cold launch would) must yield byte-identical results across calls.
    func testRepeatedDecodeOfTheSameStoredStringIsStable() {
        let encoded = DashboardCardPrefs.encode([.calories, .skinTemp, .stress])
        let first = DashboardCardPrefs.decodeEnabled(encoded)
        let second = DashboardCardPrefs.decodeEnabled(encoded)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, [.calories, .skinTemp, .stress])
    }

    func testAcceptsTheJSONArrayForm() {
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(#"["hrv","stress"]"#), [.hrv, .stress])
    }

    /// Legacy comma-joined form (predates the JSON-array switch) must still decode, so nobody's saved
    /// selection is silently wiped by a format change.
    func testAcceptsTheLegacyCommaJoinedForm() {
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled("hrv,stress"), [.hrv, .stress])
    }

    func testDropsUnknownIdsAndCollapsesDuplicates() {
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(#"["hrv","bogus","hrv","stress"]"#), [.hrv, .stress])
    }

    /// A saved string that decodes to NO known card (every id stale/unrecognised) must fall back to the
    /// default selection, never to an empty dashboard.
    func testAllUnknownIdsFallBackToDefaultSelectionNotAnEmptyDashboard() {
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(#"["bogus","nope"]"#), DashboardCard.defaultSelection)
        XCTAssertFalse(DashboardCardPrefs.decodeEnabled(#"["bogus","nope"]"#).isEmpty)
    }

    func testDefaultSelectionCardsAreAllKnown() {
        for card in DashboardCard.defaultSelection {
            XCTAssertTrue(DashboardCard.canonicalOrder.contains(card))
        }
    }

    func testCardRawKeysAreStableAndUnique() {
        let raws = DashboardCard.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, Set(raws).count, "raw keys must be unique (they're the persisted identity)")
        // Pin the exact wire strings — they must match the Android DashboardCard byte-for-byte.
        XCTAssertEqual(
            raws,
            ["hrv", "restingHr", "respiratory", "steps", "stress", "fitnessAge", "vitality",
             "bloodOxygen", "skinTemp", "sleep", "calories", "hydration", "coupled"]
        )
    }

    /// End-to-end persistence through a throwaway UserDefaults suite, exactly as `@AppStorage(DashboardCardPrefs.
    /// selectionKey)` would read/write it — pins the key name itself, not just the pure encode/decode functions.
    func testCustomisationPersistsThroughUserDefaults() {
        let suite = "DashboardCardPrefsTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Fresh install: nothing written yet, reads as the default selection.
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(defaults.string(forKey: DashboardCardPrefs.selectionKey) ?? ""),
                       DashboardCard.defaultSelection)

        // User customises: adds the optional Coupled-view card and drops Vitality.
        defaults.set(DashboardCardPrefs.encode([.stress, .fitnessAge, .hrv, .restingHr, .coupled]),
                     forKey: DashboardCardPrefs.selectionKey)

        // "Relaunch": a brand-new UserDefaults handle onto the SAME suite reads the persisted choice back.
        let relaunched = UserDefaults(suiteName: suite)!
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(relaunched.string(forKey: DashboardCardPrefs.selectionKey) ?? ""),
                       [.stress, .fitnessAge, .hrv, .restingHr, .coupled])

        defaults.removePersistentDomain(forName: suite)
    }
}
