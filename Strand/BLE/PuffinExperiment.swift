import Foundation

/// Opt-in switch for the EXPERIMENTAL WHOOP 5.0/MG ("puffin") protocol probes.
///
/// Live HR on a 5/MG strap already works over the standard profile after CLIENT_HELLO. These probes
/// go further — sending puffin-framed commands (e.g. asking the strap to start its realtime stream)
/// to learn what a real 5/MG strap responds to. They are guesses, so they are OFF by default and only
/// ever written to the puffin command characteristic (fd4b0002). A 5/MG owner can flip this on under
/// Settings → Experimental to help map the protocol; everyone else is unaffected.
enum PuffinExperiment {
    /// Shared with the Settings toggle via `@AppStorage(PuffinExperiment.defaultsKey)`.
    static let defaultsKey = "noopPuffinExperiments"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// Separate, more-deliberate opt-in for the WHOOP 5/MG "R22" deep-data unlock — the one probe
    /// that WRITES a persistent feature flag to the strap (the `enable_r22_*` SET_CONFIG sequence the
    /// official app sends; documented by judes.club + Asherlc/dofek). Kept distinct from the read-only
    /// probes above because it changes strap state, so it must be turned on explicitly and is still
    /// fully reversible. Driven only from `BLEManager.enableWhoop5DeepData()`. (#174)
    static let deepDataKey = "noopWhoop5DeepData"

    static var deepDataEnabled: Bool { UserDefaults.standard.bool(forKey: deepDataKey) }

    /// Opt-in "Broadcast heart rate": writes the device-config flag `whoop_live_hr_in_adv_ind_pkt="1"`
    /// so the strap advertises the standard Heart Rate Service (0x180D) + its live HR, pairable by a
    /// Garmin/Zwift/gym HR client. Reversible, default off; applied on each 5/MG connection and driven by
    /// `BLEManager.setBroadcastHr(_:)`. Mirrors the Android `PuffinExperiment.KEY_BROADCAST_HR`. (#181)
    static let broadcastHrKey = "noopBroadcastHr"

    static var broadcastHrEnabled: Bool { UserDefaults.standard.bool(forKey: broadcastHrKey) }

    /// Opt-in "Continuous HRV capture": hold the dense realtime HR stream armed even with no Live screen
    /// open, so the strap banks beat-to-beat R-R intervals 24/7 for far better overnight HRV/recovery/
    /// sleep (vs the sparse history offload). Uses more battery (continuous HR streaming). Default OFF;
    /// applied on launch + each (re)bond and driven by `BLEManager.setKeepRealtimeForData(_:)`. Mirrors
    /// the Android `NoopPrefs.KEY_CONTINUOUS_HRV`. Works on WHOOP 4 and 5/MG (both emit 0x2A37 R-R).
    static let keepRealtimeForDataKey = "noopContinuousHrv"

    static var keepRealtimeForDataEnabled: Bool { UserDefaults.standard.bool(forKey: keepRealtimeForDataKey) }

    /// Opt-in "Overnight only" refinement of Continuous HRV capture (#927): arm the dense realtime stream
    /// only inside the nightly window (the reused quiet-hours window convention: minutes since local
    /// midnight, wrap-aware, 22:00 to 07:00 by default) instead of 24/7, roughly halving the battery
    /// cost. Composed with the base toggle so existing users need no migration: base on + this off reads
    /// ALWAYS (the pre-#927 behaviour). Default OFF. Read by BLEManager at EVERY arm site (re-derived at
    /// arm time, never precomputed; see ContinuousHrvSchedule). Mirrors the Android
    /// `NoopPrefs.KEY_CONTINUOUS_HRV_OVERNIGHT`.
    static let continuousHrvOvernightOnlyKey = "noopContinuousHrvOvernightOnly"

    static var continuousHrvOvernightOnlyEnabled: Bool { UserDefaults.standard.bool(forKey: continuousHrvOvernightOnlyKey) }

    // MARK: - Power saving (#477), parity with Android NoopPrefs

    /// "Power saving" master: battery-adaptive strap-sync cadence. Default off. */
    static let powerSavingKey = "noopPowerSaving"
    static var powerSavingEnabled: Bool { UserDefaults.standard.bool(forKey: powerSavingKey) }

    /// Battery-% threshold for power saving (10–30). Default 20 (0 in the store means "unset" → 20).
    static let powerSavingBatteryPctKey = "noopPowerSavingBatteryPct"
    static var powerSavingBatteryPct: Int {
        let v = UserDefaults.standard.integer(forKey: powerSavingBatteryPctKey)
        return v == 0 ? 20 : v
    }

    /// "Pause HRV capture under Low Power Mode" — a sub-option of power saving, default ON when the master
    /// is on. Stored inverted (`…Disabled`) so the default-true reads correctly from a zero-value store.
    static let pauseHrvDisabledKey = "noopPowerSavingPauseHrvDisabled"
    static var pauseHrvOnPowerSaveEnabled: Bool { !UserDefaults.standard.bool(forKey: pauseHrvDisabledKey) }

    /// "Experimental sleep staging (V2)": re-stage each detected night with `SleepStagerV2` — a transparent
    /// cardiorespiratory recipe (reimplemented from contributor PR #600) — instead of the older V1 stager.
    /// Pure analysis switch: it changes ONLY which staging engine runs over an already-detected sleep window;
    /// sleep DETECTION, scoring and the V1 path are all untouched. Model-agnostic (WHOOP 4 and 5). **Default
    /// ON**: V2 was promoted to the default staging engine after a 44-subject cross-subject benchmark (AAUWSS
    /// + Walch sleep-accel, leave-one-subject-out) showed V2 strictly dominates V1 (kappa 0.35 vs 0.03, deep
    /// recall 55 % vs 1 %) — the multi-subject validation this recipe originally lacked. V1 remains available.
    /// Read at the staging call site (Repository). Mirrors the Android `PuffinExperiment.KEY_EXPERIMENTAL_SLEEP_V2`.
    static let experimentalSleepV2Key = "noopExperimentalSleepV2"

    /// Default ON when the key is unset (mirrors the Android `getBoolean(KEY, true)`): a `bool(forKey:)` alone
    /// reads a missing key as false, so an absent preference must resolve to the promoted V2 default explicitly.
    static var experimentalSleepV2Enabled: Bool {
        UserDefaults.standard.object(forKey: experimentalSleepV2Key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: experimentalSleepV2Key)
    }

    /// Opt-in "HR-from-PPG sub-lag interpolation" (default off): the v26 optical-PPG gap-fill HR estimator
    /// (`PpgHr`) refines its integer autocorrelation lag with a parabolic (Variant A) interpolation of the
    /// ACF peak, removing the ~±8 bpm lag-quantization near a high HR. Pure opt-in research variant: default
    /// OFF is byte-identical to the integer-lag estimate, and it only ever fills seconds the strap never
    /// reported an HR for (it NEVER overrides a WHOOP-stored HR). The pure `PpgHr` package cannot read prefs,
    /// so the app-layer call site (the Backfiller / archive replay) reads this flag and threads it into the
    /// estimator. Mirrors the Android `PuffinExperiment.KEY_PPG_HR_SUBLAG_INTERP`.
    static let ppgHrSubLagInterpKey = "noopPpgHrSubLagInterp"

    static var ppgHrSubLagInterpEnabled: Bool { UserDefaults.standard.bool(forKey: ppgHrSubLagInterpKey) }

    /// Opt-in experimental "HRV readiness (Plews/Altini)" tier readout (default off): a read-only Test Centre
    /// readout of the SWC log-HRV tier (`HRVReadiness`). It changes NOTHING downstream — the Charge ring stays
    /// byte-identical whether on or off; it only surfaces the tier + baseline band in the Experimental
    /// algorithms card. Rough / early (n=1, not yet validated against varying real data). Read directly by the
    /// Test Centre view via @AppStorage on this key. Mirrors the Android `PuffinExperiment.KEY_HRV_READINESS`.
    static let hrvReadinessKey = "noopHrvReadiness"

    /// Opt-in "Auto-detect workouts": after a sync / on Today appear, scan the last day or two of HR for a
    /// SUSTAINED-ELEVATED window (resting HR + 30 bpm held ≥ 12 min) that doesn't overlap a saved workout,
    /// and surface ONE dismissible Today card offering to save it as a manual-style workout. Pure read +
    /// suggestion: nothing is ever created without the user tapping Save, and turning this OFF stops all
    /// detection and hides the card. Default OFF. Mirrors the Android `NoopPrefs.KEY_AUTO_DETECT_WORKOUTS`.
    static let autoDetectWorkoutsKey = "noopAutoDetectWorkouts"

    static var autoDetectWorkoutsEnabled: Bool { UserDefaults.standard.bool(forKey: autoDetectWorkoutsKey) }

    /// "Journal reminder" (#627). When ON, Today shows a persistent journal widget (a last-7-days
    /// completion strip that taps through to the journal) and nudges when today isn't logged yet.
    /// Default ON — gates both the widget and (on Android) the morning sleep sheet. Mirrors the Android
    /// `NoopPrefs.KEY_JOURNAL_REMINDER_ENABLED`. Default-true, so a bare `bool(forKey:)` can't be used to
    /// read it (that defaults false); read it through @AppStorage(...) = true or `object(forKey:)`.
    static let journalReminderKey = "noopJournalReminder"

    static var journalReminderEnabled: Bool {
        UserDefaults.standard.object(forKey: journalReminderKey) as? Bool ?? true
    }

    /// Opt-in "Motion-aware wake refinement" (default OFF, #364 "Proposal 2" follow-up): a post-pass
    /// (`WakeMotionRefinement`) over the already-staged hypnogram that reclassifies a scored WAKE segment
    /// to `light` when its per-minute step-tick cadence shows no locomotion AND its per-minute gravity
    /// posture stays stable outside a minority of isolated "turn-over" burst minutes (which are kept as
    /// wake). Targets the HR-led wake call misreading a hot-but-still/atonic stretch as an awakening — a
    /// real anonymized night scored 194 min wake from single-minute turn-over bursts with zero walking
    /// cadence between them. Self-gates on the OBSERVED gravity + step-sample density (never on strap
    /// family/model, per #345): a WHOOP 4.0 night (sparse gravity, no step stream at all) fails the gate
    /// and is left untouched every time; a WHOOP 5.0/MG night, which streams both densely, is the expected
    /// beneficiary. Pure analysis switch — it only ever SHRINKS an already-scored wake segment, never
    /// invents wake time; detection and the V1/V2 staging engines are untouched either way. Read at the
    /// staging call sites (`Repository.restageFromRaw`, `IntelligenceEngine`, threaded through
    /// `AnalyticsEngine.analyzeDay`). Mirrors the Android `PuffinExperiment.KEY_MOTION_AWARE_WAKE`.
    static let motionAwareWakeKey = "noopMotionAwareWake"

    static var motionAwareWakeEnabled: Bool { UserDefaults.standard.bool(forKey: motionAwareWakeKey) }

    /// Opt-in, deliberately SEPARATE switch for the EXPERIMENTAL WHOOP MG raw-ECG/electrode probe.
    /// Sourced from an unverified community report (not from this repo, no HCI capture, no confirmed
    /// packet layout) that opcode 63 (`SEND_R10_R11_REALTIME`) plus the `enable_r22_*` flags surfaces an
    /// ECG channel on a WHOOP MG's type-43 raw stream once a finger is on the strap's electrode. NOOP
    /// already implements both primitives (`Whoop5Config`, `WhoopCommand.sendR10R11Realtime`) for the
    /// confirmed, hardware-verified motion/optical stream; this toggle only chooses to arm the same
    /// already-safe/reversible opcode 63 for a bounded ~30s research window instead of NOOP's default
    /// OFF, and durably logs every type-43 frame seen during that window RAW, with NO interpretation
    /// (`PuffinEcgProbeLog`). No new/unconfirmed opcode is ever sent by this toggle alone.
    ///
    /// Kept separate from `deepDataKey` (R22 unlock) and `PuffinFrameRecorder.enabledKey` (general
    /// capture) because it targets a body-contact sensor and rests on much thinner evidence than the R22
    /// unlock — turning it off must not disable the well-evidenced R22/motion work. Default OFF.
    /// WHOOP 5/MG only. NOTE: this repo cannot distinguish plain WHOOP 5.0 from 5.0/MG in the device
    /// registry (`DeviceFamily` has only `.whoop4`/`.whoop5`, and the Add-Device wizard labels every
    /// 5-class strap "5.0 MG" — see `DeviceFamily.forRegistryModel`), so "MG only" here means "any 5/MG
    /// family connection"; a plain non-MG 5.0 strap is expected to either ignore the probe or answer
    /// "unsupported" per the same community report. Driven only by
    /// `BLEManager.captureExperimentalEcgProbe()`. Never feeds any metric, score, or downstream gate —
    /// raw capture only. See docs/WHOOP5_DEEP_DATA.md "Experimental: raw ECG / electrode channel probe".
    static let ecgProbeKey = "noopEcgProbe"

    static var ecgProbeEnabled: Bool { UserDefaults.standard.bool(forKey: ecgProbeKey) }
}
