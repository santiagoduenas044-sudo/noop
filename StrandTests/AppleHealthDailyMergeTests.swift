import XCTest
import WhoopStore
@testable import Strand

/// Pins the Apple-Health arm of `Repository.mergeDaily`.
///
/// Regression context: `refresh()` read the `apple-health` daily rows and fed them ONLY to
/// `sourceRows` / `computeFreshness` — never into the merge that produces `repo.days`. Every screen
/// reads `repo.days`, so any signal Apple Health was the sole source of was invisible app-wide.
/// SpO₂ was the visible casualty: the on-device engine banks raw `spo2Red`/`spo2Ir` and writes
/// `spo2Pct = nil` (see `WhoopStore.lastSpo2Day`), so a strap user whose only real percentage came
/// from an Apple Watch saw an empty Blood Oxygen surface no matter how much data Health held.
///
/// The contract these tests pin: Apple Health is the LOWEST-priority real source
/// (`DailyMetricSource.vitalPriority`: whoopImport 0 < noopComputed 1 < appleHealth 2). It fills
/// gaps and supplies whole days nothing else covered — it must never overwrite a strap measurement
/// or a NOOP-computed value.
final class AppleHealthDailyMergeTests: XCTestCase {

    /// The actual reported bug: strap row present, its `spo2Pct` nil, Apple Health holds the real
    /// reading. Before the fix `merged[0].spo2Pct` was nil and Blood Oxygen rendered empty.
    func testAppleHealthFillsSpo2WhenStrapRowHasNone() {
        let imported = daily(day: "2026-08-04", totalSleepMin: 430, spo2Pct: nil, respRateBpm: 14.2)
        let apple = daily(day: "2026-08-04", spo2Pct: 96.8)

        let merged = Repository.mergeDaily(imported: [imported], computed: [], apple: [apple])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].spo2Pct, 96.8, "Apple Health must fill an SpO2 gap the strap left nil")
        // …without disturbing anything the strap did measure.
        XCTAssertEqual(merged[0].totalSleepMin, 430)
        XCTAssertEqual(merged[0].respRateBpm, 14.2)
    }

    /// Apple is the lowest-priority real source, so a value it also holds must lose to both the
    /// imported strap row and the NOOP-computed row.
    func testAppleHealthNeverOverwritesHigherPrioritySources() {
        let imported = daily(day: "2026-08-04", spo2Pct: 97.5, steps: 8_000)
        let computed = daily(day: "2026-08-04", recovery: 71)
        let apple = daily(day: "2026-08-04", recovery: 40, spo2Pct: 90.1, steps: 12_345)

        let merged = Repository.mergeDaily(imported: [imported], computed: [computed], apple: [apple])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].spo2Pct, 97.5, "imported strap SpO2 must win over Apple Health")
        XCTAssertEqual(merged[0].recovery, 71, "NOOP-computed recovery must win over Apple Health")
        XCTAssertEqual(merged[0].steps, 8_000, "imported steps must win over Apple Health")
    }

    /// A day no strap or computed row covers should still surface from Apple Health rather than
    /// being dropped — otherwise an Apple-Watch-only stretch of history is silently missing.
    func testAppleOnlyDaySurvivesTheMerge() {
        let imported = daily(day: "2026-08-01", spo2Pct: 97)
        let appleOnly = daily(day: "2026-08-02", spo2Pct: 95.5)

        let merged = Repository.mergeDaily(imported: [imported], computed: [], apple: [appleOnly])

        XCTAssertEqual(merged.map(\.day), ["2026-08-01", "2026-08-02"], "merge is sorted oldest→newest")
        XCTAssertEqual(merged[1].spo2Pct, 95.5)
    }

    /// Passing no Apple rows must reproduce the pre-fix merge exactly, so the new parameter can't
    /// have shifted behaviour for installs with Health disabled.
    func testOmittingAppleRowsIsUnchangedBehaviour() {
        let imported = daily(day: "2026-08-04", totalSleepMin: 400, spo2Pct: 97)
        let computed = daily(day: "2026-08-04", totalSleepMin: 380, recovery: 65)

        let withEmpty = Repository.mergeDaily(imported: [imported], computed: [computed], apple: [])
        let withoutArg = Repository.mergeDaily(imported: [imported], computed: [computed])

        XCTAssertEqual(withEmpty, withoutArg)
        XCTAssertEqual(withEmpty[0].totalSleepMin, 400)
        XCTAssertEqual(withEmpty[0].recovery, 65)
    }

    /// The edited-night rule (computed sleep wins on a hand-edited day) must survive the Apple pass.
    func testUserEditedSleepStillWinsWithAppleRowsPresent() {
        let imported = daily(day: "2026-08-04", totalSleepMin: 400)
        let computed = daily(day: "2026-08-04", totalSleepMin: 455)
        let apple = daily(day: "2026-08-04", totalSleepMin: 300, spo2Pct: 96)

        let merged = Repository.mergeDaily(imported: [imported], computed: [computed],
                                           apple: [apple], userEditedDays: ["2026-08-04"])

        XCTAssertEqual(merged[0].totalSleepMin, 455, "the hand-edited computed sleep must still win")
        XCTAssertEqual(merged[0].spo2Pct, 96, "Apple still fills the SpO2 gap on an edited day")
    }

    // MARK: - Helper

    private func daily(
        day: String,
        totalSleepMin: Double? = nil,
        recovery: Double? = nil,
        spo2Pct: Double? = nil,
        respRateBpm: Double? = nil,
        steps: Int? = nil
    ) -> DailyMetric {
        DailyMetric(
            day: day,
            totalSleepMin: totalSleepMin,
            efficiency: nil,
            deepMin: nil,
            remMin: nil,
            lightMin: nil,
            disturbances: nil,
            restingHr: nil,
            avgHrv: nil,
            recovery: recovery,
            strain: nil,
            exerciseCount: nil,
            spo2Pct: spo2Pct,
            skinTempDevC: nil,
            respRateBpm: respRateBpm,
            steps: steps
        )
    }
}
