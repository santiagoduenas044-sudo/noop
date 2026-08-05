import XCTest
@testable import Strand

/// Pins the factor-library data (not UI) and the `JournalCatalogItem` Codable contract that lets
/// `favorite` exist without corrupting a user's already-persisted journal customisation.
final class JournalFactorLibraryTests: XCTestCase {

    /// The library must never offer the SAME behaviour twice under two different strings — that
    /// would let a user log what looks like two factors that are actually one, splitting its
    /// history (and the with/without sample size) in half for no reason.
    func testNoDuplicateCanonicalsWithinTheLibrary() {
        var seen = Set<String>()
        var dups: [String] = []
        for f in JournalFactorLibrary.all {
            let key = JournalCatalogStore.norm(f.canonical)
            if !seen.insert(key).inserted { dups.append(f.canonical) }
        }
        XCTAssertTrue(dups.isEmpty, "Duplicate canonicals in the library: \(dups)")
    }

    /// The library must never re-offer a starter question under different wording — the point of
    /// the library is to COMPLEMENT the starters, and a near-duplicate would confuse "which one did
    /// I actually log history under" without the user ever intending two separate factors.
    func testNoOverlapWithStarterQuestions() {
        let starterKeys = Set(JournalCatalogStore.starterQuestions.map(JournalCatalogStore.norm))
        let overlap = JournalFactorLibrary.all.filter { starterKeys.contains(JournalCatalogStore.norm($0.canonical)) }
        XCTAssertTrue(overlap.isEmpty, "Library duplicates a starter question: \(overlap.map(\.canonical))")
    }

    /// Every factor's `canonical` must be non-empty and pre-trimmed — the addFromLibrary path
    /// doesn't re-trim, unlike the free-text custom-add path, since a library entry is fixed data
    /// rather than user input.
    func testEveryCanonicalIsNonEmptyAndTrimmed() {
        for f in JournalFactorLibrary.all {
            XCTAssertFalse(f.canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Empty canonical in the library")
            XCTAssertEqual(f.canonical, f.canonical.trimmingCharacters(in: .whitespacesAndNewlines),
                           "Canonical carries leading/trailing whitespace: '\(f.canonical)'")
        }
    }

    /// A `.scale` factor's range must be non-empty and sane (this app renders it as a row of tap
    /// targets — an empty or absurdly large range would produce a broken or unusable control).
    func testScaleRangesAreSane() {
        for f in JournalFactorLibrary.all {
            if case let .scale(range) = f.kind {
                XCTAssertGreaterThanOrEqual(range.count, 2, "\(f.canonical): scale needs at least 2 points")
                XCTAssertLessThanOrEqual(range.count, 10, "\(f.canonical): scale range implausibly large")
            }
        }
    }

    /// `.quantity` and `.duration` must carry a real (non-empty) unit label — that's the whole
    /// point of distinguishing them from plain `.numeric`.
    func testQuantityAndDurationCarryAUnit() {
        for f in JournalFactorLibrary.all {
            switch f.kind {
            case .quantity(let u):
                XCTAssertFalse(u.isEmpty, "\(f.canonical): .quantity with no unit label")
            case .duration(let u):
                XCTAssertFalse(u.isEmpty, "\(f.canonical): .duration with no unit label")
            default:
                break
            }
        }
    }

    // MARK: - JournalCatalogItem Codable (the `favorite` migration safety net)

    /// The actual regression this guards: a JSON blob persisted BEFORE `favorite` existed (no
    /// "favorite" key at all) must still decode — with `favorite` defaulting to false — rather than
    /// throwing and silently discarding the user's saved journal customisation on first launch
    /// after the update. Builds the "old blob" by encoding a real item and stripping the new key,
    /// rather than hand-typing the enum's JSON shape, so this doesn't depend on knowing exactly how
    /// Swift's Codable synthesis represents `JournalKind`'s cases on the wire.
    func testDecodingAnOldBlobWithoutFavoriteDefaultsToFalse() throws {
        let current = JournalCatalogItem(canonical: "Did you take magnesium?", displayName: nil,
                                         kind: .bool, group: .supplements, sortIndex: 0,
                                         hidden: false, custom: false, favorite: false)
        let data = try JSONEncoder().encode(current)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("expected a JSON object")
        }
        XCTAssertNotNil(obj["favorite"], "sanity check: current encoding does include favorite")
        obj.removeValue(forKey: "favorite")   // simulate a pre-favorite persisted blob
        let oldData = try JSONSerialization.data(withJSONObject: obj)

        let decoded = try JSONDecoder().decode(JournalCatalogItem.self, from: oldData)
        XCTAssertEqual(decoded.canonical, "Did you take magnesium?")
        XCTAssertFalse(decoded.favorite, "favorite must default to false when absent from old data")
    }

    /// Round-trip: encode, decode, and confirm every field — including the new one — survives.
    func testFavoriteRoundTripsThroughEncodeDecode() throws {
        let item = JournalCatalogItem(canonical: "Took melatonin", displayName: "Melatonin",
                                      kind: .quantity(unitLabel: "mg"), group: .supplements,
                                      sortIndex: 3, hidden: false, custom: true, favorite: true)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(JournalCatalogItem.self, from: data)
        XCTAssertEqual(decoded, item)
        XCTAssertTrue(decoded.favorite)
    }

    /// A whole array of items — the actual persisted shape (`journal.catalog.v2` is `[JournalCatalogItem]`,
    /// not one item) — must round-trip too, mixing kinds including the new response types.
    func testItemArrayRoundTripsWithMixedKinds() throws {
        let items = [
            JournalCatalogItem(canonical: "Stress level", displayName: nil, kind: .scale(range: 1...5),
                               group: .subjective, sortIndex: 0, hidden: false, custom: true, favorite: true),
            JournalCatalogItem(canonical: "Last caffeine", displayName: nil, kind: .time,
                               group: .caffeine, sortIndex: 1, hidden: false, custom: true),
            JournalCatalogItem(canonical: "Alcohol", displayName: nil,
                               kind: .multiSelect(options: ["Wine", "Beer", "Spirits"]),
                               group: .nutrition, sortIndex: 2, hidden: true, custom: false),
        ]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([JournalCatalogItem].self, from: data)
        XCTAssertEqual(decoded, items)
    }

    // MARK: - multiSelectKey

    func testMultiSelectKeyJoinsFactorAndOption() {
        XCTAssertEqual(JournalCatalogItem.multiSelectKey(factor: "Alcohol", option: "Wine"),
                       "Alcohol — Wine")
    }
}
