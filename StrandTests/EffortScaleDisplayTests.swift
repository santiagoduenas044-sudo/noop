import XCTest
import StrandAnalytics
@testable import Strand

/// Pins the Effort/strain display-scale contract that produced the impossible "27 / 21".
///
/// `DailyMetric.strain` is STORED on NOOP's native 0–100 axis (`StrainScorer.maxStrain` = 100).
/// WHOOP's Day Strain axis is 0–21 and the user chooses which they see. Every Premium surface read
/// the stored value RAW and then rendered it against a hardcoded 0–21 gauge, so a perfectly valid
/// stored strain of 27 displayed as "27 / 21".
///
/// The fix routes every Premium strain read through `UnitFormatter.effortValue` and every gauge
/// denominator through `UnitFormatter.effortAxisMax` — the two helpers tested here.
/// `PremiumMetricCatalog.strainDisplay` / `.strainScaleMax` are thin wrappers over exactly these, but
/// they live under `#if os(iOS)` and there is no iOS unit-test target, so the contract is pinned at
/// this shared layer and the iOS wiring is validated by the app-target build.
final class EffortScaleDisplayTests: XCTestCase {

    /// The stored full-scale value the display layer restates must stay tied to the analytics
    /// constant it mirrors — if `StrainScorer.maxStrain` ever moves, the axis must move with it.
    func testStoredMaxMatchesTheAnalyticsConstant() {
        XCTAssertEqual(UnitFormatter.effortStoredMax, StrainScorer.maxStrain, accuracy: 1e-9)
    }

    /// The bug, stated as an invariant: a full-scale stored value must land exactly on the top of
    /// whichever axis is displayed — never past it.
    func testFullScaleStoredStrainNeverExceedsTheDisplayedAxis() {
        XCTAssertEqual(UnitFormatter.effortValue(100, scale: .whoop), 21, accuracy: 1e-9)
        XCTAssertEqual(UnitFormatter.effortValue(100, scale: .hundred), 100, accuracy: 1e-9)
    }

    /// The exact reported symptom: a stored 27 must NOT render as 27 on the 0–21 axis.
    func testStoredTwentySevenDoesNotRenderAsTwentySevenOutOfTwentyOne() {
        let shown = UnitFormatter.effortValue(27, scale: .whoop)
        XCTAssertEqual(shown, 27 * 21.0 / 100.0, accuracy: 1e-9)
        XCTAssertLessThan(shown, 21, "a mid-range day must sit well inside the axis")
    }

    /// Sweep the whole stored domain on both axes — no input may ever produce a value above the
    /// axis maximum, which is what makes an impossible reading structurally unreachable.
    func testNoStoredValueCanExceedTheAxisMaximum() {
        for scale in [EffortScale.whoop, EffortScale.hundred] {
            let maxAxis = UnitFormatter.effortAxisMax(scale)
            for stored in stride(from: 0.0, through: UnitFormatter.effortStoredMax, by: 0.5) {
                let shown = UnitFormatter.effortValue(stored, scale: scale)
                XCTAssertGreaterThanOrEqual(shown, 0, "scale \(scale.rawValue), stored \(stored)")
                XCTAssertLessThanOrEqual(shown, maxAxis + 1e-9,
                                         "scale \(scale.rawValue), stored \(stored) rendered \(shown) above axis \(maxAxis)")
            }
        }
    }

    /// The axis maximum and the conversion must agree — if one is changed without the other, the
    /// gauge and its label drift apart again, which is the whole shape of this bug.
    func testAxisMaximumMatchesAFullScaleConversion() {
        for scale in [EffortScale.whoop, EffortScale.hundred] {
            XCTAssertEqual(UnitFormatter.effortValue(UnitFormatter.effortStoredMax, scale: scale),
                           UnitFormatter.effortAxisMax(scale), accuracy: 1e-9,
                           "scale \(scale.rawValue): full-scale conversion must equal the axis max")
        }
    }

    /// The numeric axis max and the STRING one shown in "/21" labels must name the same number.
    func testNumericAndStringAxisMaximaAgree() {
        for scale in [EffortScale.whoop, EffortScale.hundred] {
            XCTAssertEqual(UnitFormatter.effortScaleMax(scale),
                           "\(Int(UnitFormatter.effortAxisMax(scale).rounded()))",
                           "scale \(scale.rawValue): label and denominator must agree")
        }
    }

    /// The preference key + resolution the display layer reads. An unset or unknown value must
    /// resolve to NOOP's native 0–100 axis, never to a partially-applied conversion.
    func testEffortScaleResolutionDefaultsToTheStoredAxis() {
        XCTAssertEqual(UnitPrefs.resolveEffortScale(""), .hundred)
        XCTAssertEqual(UnitPrefs.resolveEffortScale("nonsense"), .hundred)
        XCTAssertEqual(UnitPrefs.resolveEffortScale(EffortScale.whoop.rawValue), .whoop)
        XCTAssertEqual(UnitPrefs.resolveEffortScale(EffortScale.hundred.rawValue), .hundred)
    }
}
