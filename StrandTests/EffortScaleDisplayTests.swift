import XCTest
import WhoopStore
@testable import Strand

/// Pins the Effort/strain display-scale contract that produced the impossible "27 / 21".
///
/// `DailyMetric.strain` is STORED on NOOP's native 0–100 axis (`StrainScorer.maxStrain` = 100).
/// WHOOP's Day Strain axis is 0–21 and the user chooses which they see. Every Premium surface read
/// the stored value RAW and then rendered it against a 0–21 gauge, so a perfectly valid stored
/// strain of 27 displayed as "27 / 21".
///
/// These tests guard the conversion helpers and — more importantly — the invariant that a converted
/// value can never exceed the axis it is drawn against.
final class EffortScaleDisplayTests: XCTestCase {

    private func withEffortScale(_ raw: String, _ body: () -> Void) {
        let key = UnitFormatter.effortScaleKey
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(raw, forKey: key)
        body()
        if let previous { UserDefaults.standard.set(previous, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// The bug, stated as an invariant: a full-scale stored value must land exactly on the top of
    /// whichever axis is displayed — never past it.
    func testFullScaleStoredStrainNeverExceedsTheDisplayedAxis() {
        withEffortScale(EffortScale.whoop.rawValue) {
            let shown = PremiumMetricCatalog.strainDisplay(100)
            XCTAssertEqual(shown, 21, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(shown, PremiumMetricCatalog.strainScaleMax)
        }
        withEffortScale(EffortScale.hundred.rawValue) {
            let shown = PremiumMetricCatalog.strainDisplay(100)
            XCTAssertEqual(shown, 100, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(shown, PremiumMetricCatalog.strainScaleMax)
        }
    }

    /// The exact reported symptom: a stored 27 must NOT render as 27 on the 0–21 axis.
    func testStoredTwentySevenDoesNotRenderAsTwentySevenOutOfTwentyOne() {
        withEffortScale(EffortScale.whoop.rawValue) {
            let shown = PremiumMetricCatalog.strainDisplay(27)
            XCTAssertEqual(shown, 27 * 21.0 / 100.0, accuracy: 1e-9)
            XCTAssertLessThan(shown, 21, "a mid-range day must sit well inside the axis")
            XCTAssertLessThanOrEqual(shown, PremiumMetricCatalog.strainScaleMax)
        }
    }

    /// Sweep the whole stored domain on both axes — no input may ever produce a value above the
    /// axis maximum, which is what makes an impossible reading structurally unreachable.
    func testNoStoredValueCanExceedTheAxisMaximum() {
        for raw in [EffortScale.whoop.rawValue, EffortScale.hundred.rawValue] {
            withEffortScale(raw) {
                let maxAxis = PremiumMetricCatalog.strainScaleMax
                for stored in stride(from: 0.0, through: 100.0, by: 0.5) {
                    let shown = PremiumMetricCatalog.strainDisplay(stored)
                    XCTAssertGreaterThanOrEqual(shown, 0, "scale \(raw), stored \(stored)")
                    XCTAssertLessThanOrEqual(shown, maxAxis + 1e-9,
                                             "scale \(raw), stored \(stored) rendered \(shown) above axis \(maxAxis)")
                }
            }
        }
    }

    /// The axis maximum and the conversion must agree — if one changes without the other, the
    /// gauge and its label drift apart again.
    func testAxisMaximumMatchesAFullScaleConversion() {
        for raw in [EffortScale.whoop.rawValue, EffortScale.hundred.rawValue] {
            withEffortScale(raw) {
                XCTAssertEqual(PremiumMetricCatalog.strainDisplay(100),
                               PremiumMetricCatalog.strainScaleMax, accuracy: 1e-9,
                               "scale \(raw): full-scale conversion must equal the axis max")
            }
        }
    }

    /// `PremiumBounds` previously capped strain at 0…21 while being fed the raw 0–100 value, so
    /// `clean` silently DISCARDED every day above 21 — truncating strain history, baselines and
    /// correlations to only the lightest days. The bound must cover the wider axis.
    func testBoundsDoNotDiscardRealStrainDays() {
        let samples = [
            PremiumSample(day: "2026-08-01", value: 8),
            PremiumSample(day: "2026-08-02", value: 42),   // a real, ordinary 0–100 day
            PremiumSample(day: "2026-08-03", value: 88),
        ]
        let cleaned = PremiumBounds.clean(samples, key: "strain")
        XCTAssertEqual(cleaned.count, 3, "no ordinary strain day may be dropped as 'impossible'")
    }

    /// Genuinely impossible values are still rejected — widening the bound must not disable it.
    func testBoundsStillRejectImpossibleStrain() {
        let samples = [
            PremiumSample(day: "2026-08-01", value: -5),
            PremiumSample(day: "2026-08-02", value: 5_000),
        ]
        XCTAssertTrue(PremiumBounds.clean(samples, key: "strain").isEmpty)
    }
}
