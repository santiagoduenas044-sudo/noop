import XCTest
import WhoopProtocol
@testable import Strand

/// Pins `PuffinEcgProbeLog.isRawDataFrame` — the pure, family-aware predicate behind the EXPERIMENTAL
/// MG ECG/electrode probe's raw capture log. `REALTIME_RAW_DATA` is type 43; the inner-record type byte
/// sits at frame offset 4 on WHOOP 4.0 (harvard) and offset 8 on WHOOP 5/MG (puffin, 4 bytes longer) —
/// the same convention `BLEManager.isOffloadFrame` and `PuffinDeepBufferLog` already use. BLE delivery
/// can't be unit-tested, but this offset selection CAN be, so a frame-shape change can't silently break
/// the probe's raw capture. Mirrors `PuffinDeepBufferLogTests`.
final class PuffinEcgProbeLogTests: XCTestCase {

    func testAcceptsType43AtOffset8ForWhoop5() {
        var f = [UInt8](repeating: 0, count: 1921) // the known "optical" variant length, for realism
        f[8] = 43
        XCTAssertTrue(PuffinEcgProbeLog.isRawDataFrame(f, family: .whoop5))
    }

    func testAcceptsType43AtOffset4ForWhoop4() {
        var f = [UInt8](repeating: 0, count: 1917) // the known "imu" variant length, for realism
        f[4] = 43
        XCTAssertTrue(PuffinEcgProbeLog.isRawDataFrame(f, family: .whoop4))
    }

    func testRejectsWrongOffsetForFamily() {
        // A WHOOP4-shaped frame (type at offset 4) must NOT match when checked as whoop5, and vice
        // versa — reading the wrong offset is exactly the bug this predicate exists to avoid.
        var whoop4Shaped = [UInt8](repeating: 0, count: 1921)
        whoop4Shaped[4] = 43
        XCTAssertFalse(PuffinEcgProbeLog.isRawDataFrame(whoop4Shaped, family: .whoop5))

        var whoop5Shaped = [UInt8](repeating: 0, count: 1917)
        whoop5Shaped[8] = 43
        XCTAssertFalse(PuffinEcgProbeLog.isRawDataFrame(whoop5Shaped, family: .whoop4))
    }

    func testRejectsOtherTypes() {
        for t: UInt8 in [40, 47, 48, 49, 50, 0x24] {
            var f5 = [UInt8](repeating: 0, count: 1921); f5[8] = t
            XCTAssertFalse(PuffinEcgProbeLog.isRawDataFrame(f5, family: .whoop5), "type \(t) must not match on whoop5")
            var f4 = [UInt8](repeating: 0, count: 1917); f4[4] = t
            XCTAssertFalse(PuffinEcgProbeLog.isRawDataFrame(f4, family: .whoop4), "type \(t) must not match on whoop4")
        }
    }

    func testRejectsTooShortToIndexTypeOffset() {
        for n in 0...4 {
            XCTAssertFalse(PuffinEcgProbeLog.isRawDataFrame([UInt8](repeating: 43, count: n), family: .whoop4))
        }
        for n in 0...8 {
            XCTAssertFalse(PuffinEcgProbeLog.isRawDataFrame([UInt8](repeating: 43, count: n), family: .whoop5))
        }
    }

    /// Deliberately NOT length-filtered (see `PuffinEcgProbeLog`'s doc comment): any length at all, not
    /// just the two known 1917/1921 variants, must match as long as the type byte is 43. This is the
    /// behavior that lets the probe notice a THIRD, currently-unknown MG payload length if one exists.
    func testMatchesRegardlessOfPayloadLength() {
        for len in [50, 500, 1917, 1921, 3000] {
            var f = [UInt8](repeating: 0, count: len)
            f[8] = 43
            XCTAssertTrue(PuffinEcgProbeLog.isRawDataFrame(f, family: .whoop5), "length \(len) must still match")
        }
    }
}
