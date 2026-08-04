import Foundation
import CoreBluetooth
import WhoopProtocol

/// Electrode-contact state the CALLER asserts for an entire `PuffinEcgProbeLog` capture window (NOOP
/// cannot detect contact itself — no confirmed field for it exists yet). Written into every line of
/// that window so two separately-labeled runs can be diffed offline without cross-referencing
/// timestamps. Top-level (not nested in `PuffinEcgProbeLog`) so it can appear in the public
/// `BLEManager.captureExperimentalEcgProbe(contact:)` signature, mirroring `RebootProbeVariant`.
public enum EcgProbeContactLabel: String, Sendable {
    case onElectrode = "on"
    case noContact = "off"
    case unspecified = "unspecified"
}

/// Durable, bounded-window, raw-only log of WHOOP 5/MG type-43 (`REALTIME_RAW_DATA`) frames captured
/// while the EXPERIMENTAL ECG probe is armed (`BLEManager.captureExperimentalEcgProbe`).
///
/// ## Why this exists — the evidence behind it
///
/// This is instrumentation for a specific, external, developer-sourced claim (Discord, WHOOP
/// third-party reverse-engineering community; **not produced or independently confirmed by this repo**):
/// a developer reported reading a WHOOP MG's real ECG waveform (raw AND filtered) "without the app,
/// purely reimplemented logic," and specifically attributed it to decoding **opcode-63 type-43 frames**
/// after enabling all R22 flags — quoting them directly: *"For MG the opcode should be 63 to get the
/// data streaming for ECG and red/ir,"* and an early capture explicitly labeled *"decoded from opcode-63
/// type-43 frames."* They demonstrated the same channel differing with a finger on the strap's electrode
/// versus no contact. NOOP already implements both primitives they named — `Whoop5Config.enableR22Sequence`
/// and `WhoopCommand.sendR10R11Realtime` (opcode 63) — hardware-verified for the known IMU/optical
/// variants (docs/BLE_REVERSE_ENGINEERING.md §4), but normally leaves opcode 63 OFF and only recognises
/// two payload lengths (1917 B `imu`, 1921 B `optical`, explicitly NOT ECG).
///
/// This file does not confirm or dispute the claim. It exists to let a WHOOP MG owner (see
/// docs/WHOOP5_DEEP_DATA.md "Experimental: raw ECG / electrode channel probe") gather the raw evidence
/// this repo needs to evaluate it: if MG really does emit a third payload length on this exact stream
/// once R22 is set, this log is where it will show up, byte-for-byte, with no risk of NOOP's own
/// decoder silently discarding it as "unknown."
///
/// ## What this file does — and does NOT do
///
/// This is **pure raw capture, zero interpretation**. It does NOT decode, filter, or attempt to identify
/// an ECG channel. It logs the **entire raw frame** for every type-43 frame seen while a capture window
/// is open — deliberately NOT length-filtered, so a frame is never discarded just because its length
/// isn't 1917 or 1921 (that exclusion is exactly what would hide the evidence this probe exists to find,
/// and this file's author does not have enough confidence in the puffin-vs-harvard byte-offset
/// arithmetic for type-43 specifically — the existing decoder's `raw_data` post-hook reads `frame[4]`
/// unconditionally, which is only correct for WHOOP 4.0 harvard framing — to safely exclude "already
/// known" frames without that risk). Offline analysis, not this file, is where the known-vs-unknown
/// split belongs.
///
/// Each capture window is tagged with a caller-supplied **contact label** (`.onElectrode` /
/// `.noContact` / `.unspecified`) so a WHOOP MG owner can run two short, separately-labeled captures —
/// finger on the electrode, then no contact — and diff them offline (grep/jq on the `"contact"` field)
/// without needing to correlate timestamps against a separate note. A `window_start` / `window_end`
/// marker line brackets every session with its label, a session id, and the strap state at the moment
/// capture began (R22 flags accepted, worn, encrypted bond) — "surrounding packet metadata" for
/// interpreting the frames between them, without touching any other part of NOOP.
///
/// Never feeds any metric, score, decoder, or UI display. Nothing here is shown as "Experimental ECG
/// waveform" or any other user-facing label — that phrase is reserved for a FUTURE decode step, once (if)
/// a real capture confirms MG actually sends something new here.
///
/// Gated on its OWN toggle (`PuffinExperiment.ecgProbeKey`), separate from the general puffin-capture
/// toggle (`PuffinFrameRecorder.enabledKey`) and from the R22 deep-data unlock toggle, because it is a
/// distinct, higher-uncertainty probe of a body-contact sensor. Only ever active inside the bounded
/// window `BLEManager.captureExperimentalEcgProbe` opens; frames arriving outside that window are never
/// written, even if the toggle is left on, so idle capture never runs 24/7 and normal NOOP acquisition
/// (HR/HRV/sleep/SpO2 decoding, the Collector, the Backfiller) is completely untouched by this file.
/// WHOOP 5/MG only (WHOOP 4.0 has no electrodes).
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

    /// Strap/session state at the moment a window opens — "surrounding packet metadata" for the frames
    /// that follow, captured once per window rather than repeated on every frame line.
    struct WindowContext {
        let r22FlagsAccepted: Int
        let worn: Bool
        let encryptedBond: Bool
    }

    private var handle: FileHandle?
    private var disabled = false

    /// True only while `BLEManager.captureExperimentalEcgProbe`'s bounded window is open. Frames are
    /// never written outside a window, regardless of the Settings toggle — the toggle only permits a
    /// window to be opened, it does not itself arm capture.
    private var windowActive = false
    private var sessionId = ""
    private var contactLabel: EcgProbeContactLabel = .unspecified
    private var frameIndex = 0

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

    /// Open a capture window and write its `window_start` marker line. Call once at the start of
    /// `captureExperimentalEcgProbe`'s bounded window. `sessionId` should be unique per tap (a short
    /// UUID prefix or timestamp is fine) so two runs never interleave under the same id.
    func beginWindow(sessionId: String, contact: EcgProbeContactLabel, context: WindowContext, seconds: TimeInterval) {
        self.sessionId = sessionId
        self.contactLabel = contact
        self.frameIndex = 0
        windowActive = true
        guard isEnabled else { return }
        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        let line = "{\"kind\":\"window_start\",\"ts_ms\":\(tsMs),\"session\":\"\(sessionId)\","
            + "\"contact\":\"\(contact.rawValue)\",\"seconds\":\(seconds),"
            + "\"r22_flags_accepted\":\(context.r22FlagsAccepted),\"worn\":\(context.worn),"
            + "\"encrypted_bond\":\(context.encryptedBond)}\n"
        writeLine(line)
    }

    /// Close the capture window: write its `window_end` marker line, then the file handle. Call once
    /// when the bounded window's timer fires.
    func endWindow() {
        if isEnabled {
            let tsMs = Int(Date().timeIntervalSince1970 * 1000)
            let line = "{\"kind\":\"window_end\",\"ts_ms\":\(tsMs),\"session\":\"\(sessionId)\","
                + "\"contact\":\"\(contactLabel.rawValue)\",\"frames\":\(frameIndex)}\n"
            writeLine(line)
        }
        windowActive = false
        close()
    }

    /// Public accessor for Settings export/reveal: the log's file URL, if it has ever been written.
    /// Deterministic path — safe to call without an active instance or window.
    static func fileURL() -> URL? {
        guard let url = try? logURL() else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
    /// `hr` is the live (standard-profile) heart rate at capture time, if known — free context, exactly
    /// what `PuffinFrameRecorder` already stamps on its captures. Returns true when the frame was
    /// appended (so the caller can drive a UI counter).
    @discardableResult
    func appendIfCandidate(frame: [UInt8], family: DeviceFamily, char: CBUUID, hr: Int?) -> Bool {
        guard !disabled, windowActive, Self.isRawDataFrame(frame, family: family), isEnabled else {
            return false
        }
        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        let hex = frame.map { String(format: "%02x", $0) }.joined()
        let hrField = hr.map { "\($0)" } ?? "null"
        // "len" is the raw byte count of the WHOLE frame as received (envelope + payload + CRC), not the
        // decoder's internal "dataLen" — deliberately, so offline analysis can compare against either
        // convention without this file guessing which one applies to a puffin-framed type-43 packet.
        let line = "{\"kind\":\"frame\",\"ts_ms\":\(tsMs),\"session\":\"\(sessionId)\","
            + "\"contact\":\"\(contactLabel.rawValue)\",\"idx\":\(frameIndex),\"len\":\(frame.count),"
            + "\"char\":\"\(char.uuidString.lowercased())\",\"hr\":\(hrField),\"hex\":\"\(hex)\"}\n"
        let wrote = writeLine(line)
        if wrote { frameIndex += 1 }
        return wrote
    }

    /// Close the handle (e.g. on disconnect) so the file is safe to share/export immediately.
    func close() {
        try? handle?.close()
        handle = nil
    }

    @discardableResult
    private func writeLine(_ line: String) -> Bool {
        guard !disabled else { return false }
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
