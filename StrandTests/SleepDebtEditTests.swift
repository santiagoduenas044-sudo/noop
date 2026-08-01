import XCTest
@testable import Strand

/// `Repository.resolvedSleepDebtMinutes`: keeps the export's `sleep_debt_min` as the baseline across a
/// user edit and adjusts it by the EXACT asleep-duration delta, so the export's accuracy survives the
/// edit instead of being replaced by the coarser need-minus-asleep approximation. Pure (no store).
final class SleepDebtEditTests: XCTestCase {

    /// An un-edited day returns the imported debt verbatim (unchanged behaviour, the fast path).
    func testUnEditedDayReturnsImportedDebtVerbatim() {
        let imported = ImportedSleepFigures(performancePct: nil, consistencyPct: nil, needMin: 480,
                                            debtMin: 45, originalSleepMin: 400)
        let debt = Repository.resolvedSleepDebtMinutes(imported: imported, actualSleepMin: 400,
                                                       fallbackNeedMin: 450, isUserEdited: false)
        XCTAssertEqual(debt, 45, "no edit → the export's own figure passes through untouched")
    }

    /// An edited night adjusts the imported debt by the exact delta between the original and the
    /// corrected asleep minutes: max(0, importedDebt + originalSleepMin - actualSleepMin).
    func testEditedNightAdjustsImportedDebtBySleepDurationDelta() {
        var imported = ImportedSleepFigures()
        imported.debtMin = 30
        imported.originalSleepMin = 420   // the export's pre-edit asleep minutes
        // The user shortened the night to 360 minutes asleep.
        let debt = Repository.resolvedSleepDebtMinutes(imported: imported, actualSleepMin: 360,
                                                       fallbackNeedMin: 450, isUserEdited: true)
        XCTAssertEqual(debt, 90, "30 + 420 - 360 = 90: shortening the night must INCREASE reported debt")
    }

    /// The delta can't go negative: lengthening an edited night below the original debt floors at 0
    /// ("credit" is never reported).
    func testEditedNightDeltaFloorsAtZero() {
        var imported = ImportedSleepFigures()
        imported.debtMin = 20
        imported.originalSleepMin = 400
        // The user LENGTHENED the night well past the original — the delta would go negative.
        let debt = Repository.resolvedSleepDebtMinutes(imported: imported, actualSleepMin: 500,
                                                       fallbackNeedMin: 450, isUserEdited: true)
        XCTAssertEqual(debt, 0, "20 + 400 - 500 = -80 → floored at 0, never a negative 'credit'")
    }

    /// An edited night whose import has no original duration to diff against falls back to the
    /// need-minus-asleep approximation, exactly as an un-imported day already does.
    func testEditedNightWithoutOriginalDurationUsesExistingFallback() {
        var imported = ImportedSleepFigures()
        imported.debtMin = 30
        imported.originalSleepMin = nil   // export never carried an original duration for this day
        let debt = Repository.resolvedSleepDebtMinutes(imported: imported, actualSleepMin: 400,
                                                       fallbackNeedMin: 450, isUserEdited: true)
        XCTAssertEqual(debt, 50, "450 - 400 = 50: no original duration → the approximate fallback")
    }

    /// No import at all (a strap-only user, no WHOOP export): the approximate fallback applies whether
    /// or not the night was edited.
    func testNoImportUsesApproximateFallback() {
        let debt = Repository.resolvedSleepDebtMinutes(imported: nil, actualSleepMin: 400,
                                                       fallbackNeedMin: 450, isUserEdited: true)
        XCTAssertEqual(debt, 50)
    }

    /// No usable asleep minutes (nil or zero) and no imported debt → nothing to report.
    func testNoDataReturnsNil() {
        XCTAssertNil(Repository.resolvedSleepDebtMinutes(imported: nil, actualSleepMin: nil,
                                                         fallbackNeedMin: 450, isUserEdited: false))
        XCTAssertNil(Repository.resolvedSleepDebtMinutes(imported: nil, actualSleepMin: 0,
                                                         fallbackNeedMin: 450, isUserEdited: false))
    }
}
