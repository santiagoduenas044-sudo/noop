import Foundation
import CoreBluetooth
import WhoopProtocol

/// Durable, bounded-window, raw-only log of WHOOP 5/MG type-43 (`REALTIME_RAW_DATA`) frames captured
/// while the EXPERIMENTAL ECG probe is armed (`BLEManager.captureExperimentalEcgProbe`).
///
/// ## Why this exists
///
/// A community report (WHOOP-app-independent, **not sourced from or verified by this repo**) claims a
/// developer read a real WHOOP MG's ECG waveform by: sending the `enable_r22_*` feature-flag sequence
/// NOOP already implements (`Whoop5Config`), then requesting the type-43 raw stream via opcode 63
/// (`SEND_R10_R11_REALTIME`) — both of which NOOP already implements and already knows are safe and
/// reversible (docs/BLE_REVERSE_ENGINEERING.md §4; NOOP normally sends this OFF on connect). The report
/// described a "channel 1" that shows a clean waveform with a finger on the strap's electrode and
/// rails/floats with no contact, and a ~30 s capture window.
///
/// NOOP's own type-43 decoder (`PostHooks.swift` `raw_data`) only recognises two Gen4/WHOOP-4.0-sourced
/// payload lengths — 1917 B (`imu`) and 1921 B (`optical`, a single PPG channel, explicitly NOT ECG). If
/// a WHOOP MG emits a third length when finger-contact ECG is active, NOOP's decoder does not know about
/// it and currently drops it into an "unknown" region without preserving the bytes anywhere durable.
///
/// ## What this file does — and does NOT do
///
/// This is **pure raw capture, zero interpretation**. It does NOT decode, filter, or attempt to identify
/// an ECG channel. It logs the **entire raw frame** for every type-43 frame seen while a capture window
/// is open, tagged with its length, so a captured session can be inspected offline (this repo, or a
/// tester's own tooling) to see whether MG emits anything besides the two known lengths. Deliberately NOT
/// length-filtered: this file's author does not have enough confidence in the puffin-vs-harvard byte-
/// offset arithmetic for type-43 frames specifically (the existing decoder's `raw_data` post-hook reads
/// `frame[4]` unconditionally, which is only correct for WHOOP 4.0 harvard framing — see
/// `BLEManager.isOffloadFrame`'s family-aware `frame[8]` note for 5/MG puffin frames) to safely exclude
/// "already known" frames without risking silently dropping the very frames this probe exists to find.
/// Capturing everything during a short, explicit, opt-in window is cheap and correct by construction;
/// offline analysis (not this file) is where the known-vs-unknown split belongs.
///
/// Never feeds any metric, score, decoder, or UI display. Nothing here is shown as "Experimental ECG
/// waveform" or any other user-facing label — that phrase is reserved for a FUTURE decode step, once (if)
/// a real capture confirms MG actually sends something new here.
///
/// Gated on its OWN toggle (`PuffinExperiment.ecgProbeKey`), separate from the general puffin-capture
/// toggle (`PuffinFrameRecorder.enabledKey`) and from the R22 deep-data unlock toggle, because it is a
/// distinct, higher-uncertainty probe of a body-contact sensor. Only ever active inside the bounded
/// window `BLEManager.captureExperimentalEcgProbe` opens; frames arriving outside that window are never
/// written, even if the toggle is left on, so idle capture never runs 24/7. WHOOP 5/MG only (WHOOP 4.0
/// has no electrodes and NOOP's WHOOP4 R10/R11 handling is unrelated to this probe).
///
/// Swift-only for now, matching `PuffinDeepBufferLog`'s precedent: this is reverse-engineering
/// instrumentation, not a shipped feature, so no Kotlin twin exists yet. If a real MG capture confirms a
/// new payload length here, decoding + a Kotlin twin are the next steps (see docs/WHOOP5_DEEP_DATA.md).
@MainActor
final class PuffinEcgProbeLog {

    /// WHOOP inner-record type byte for `REALTIME_RAW_DATA` (type 43 / 0x2B).
    private static let rawDataTypeByte: UInt8 = 43

    /// Cap matches `PuffinDeepBufferLog`: these frames are ~2 KB each and arrive at ~2/s while the probe
    /// is armed, so a 30 s window is at most ~120 KB — generous headroom, rotation bounds total disk.
    private static let softCapBytes = 20 * 1024 * 1024

    private var handle: FileHandle?
    private var disabled = false

    /// True only while `BLEManager.captureExperimentalEcgProbe`'s bounded window is open. Frames are
    /// never written outside a window, regardless of the Settings toggle — the toggle only permits a
    /// window to be opened, it does not itself arm capture.
    private var windowActive = false

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: PuffinExperiment.ecgProbeKey)
    }

    /// Pure predicate: is `frame` a type-43 `REALTIME_RAW_DATA` frame for the given family? Family-aware
    /// per `BLEManager.isOffloadFrame`'s established convention (puffin frames carry the inner type byte
    /// 4 bytes later than WHOOP 4.0 harvard frames). Extracted so the offset is unit-testable without a
    /// strap.
    nonisolated static func isRawDataFrame(_ frame: [UInt8], family: DeviceFamily) -> Bool {
        let typeIndex = family == .whoop5 ? 8 : 4
        guard frame.count > typeIndex else { return false }
        return frame[typeIndex] == rawDataTypeByte
    }

    /// Open a capture window. Call once at the start of `captureExperimentalEcgProbe`'s bounded window.
    func beginWindow() {
        windowActive = true
    }

    /// Close the capture window and the file handle. Call once when the bounded window's timer fires.
    func endWindow() {
        windowActive = false
        close()
    }

    /// `<AppSupport>/OpenWhoop/puffin-ecg-probe.jsonl`.
    private static func logURL() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                             appropriateFor: nil, create: true)
            .appendingPathComponent("OpenWhoop", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("puffin-ecg-probe.jsonl")
    }

    /// Append `frame` verbatim if a capture window is open, the frame is type-43, and capture is
    /// enabled. Cheap for every other frame: a length + single-byte compare before either flag is read.
    /// Returns true when the frame was appended (so the caller can drive a UI counter).
    @discardableResult
    func appendIfCandidate(frame: [UInt8], family: DeviceFamily, char: CBUUID) -> Bool {
        guard !disabled, windowActive, Self.isRawDataFrame(frame, family: family), isEnabled else {
            return false
        }
        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        let hex = frame.map { String(format: "%02x", $0) }.joined()
        // "len" is the raw byte count of the WHOLE frame as received (envelope + payload + CRC), not the
        // decoder's internal "dataLen" — deliberately, so offline analysis can compare against either
        // convention without this file guessing which one applies to a puffin-framed type-43 packet.
        let line = "{\"ts_ms\":\(tsMs),\"len\":\(frame.count),\"char\":\"\(char.uuidString.lowercased())\",\"hex\":\"\(hex)\"}\n"
        do {
            var h = try openHandle()
            if try h.offset() > UInt64(Self.softCapBytes) {
                close()
                h = try openHandle()
            }
            try h.write(contentsOf: Data(line.utf8))
            return true
        } catch {
            // A diagnostics log must never affect the connection path: disable for this launch.
            disabled = true
            return false
        }
    }

    /// Close the handle (e.g. on disconnect) so the file is safe to share/export immediately.
    func close() {
        try? handle?.close()
        handle = nil
    }

    private func openHandle() throws -> FileHandle {
        if let handle = handle { return handle }
        let url = try Self.logURL()
        let fm = FileManager.default
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > Self.softCapBytes {
            let old = url.deletingPathExtension().appendingPathExtension("jsonl.1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        handle = h
        return h
    }
}
