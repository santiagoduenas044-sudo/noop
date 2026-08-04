# WHOOP 5.0 / MG deep data — the "R22" unlock

**Status:** experimental, opt-in, awaiting on-hardware confirmation.
**Tracking:** [#103](https://github.com/ryanbr/noop/issues/103) (raw HCI captures + new deep-record layouts).

## The problem

A WHOOP 5.0 / MG strap hands a freshly-connected third-party client **only live heart rate** (over the
standard `0x2A37` profile, which needs no bond). Recovery, strain, sleep, motion and history don't come
through. This is the single biggest gap in NOOP's 5/MG support, and it affects every independent WHOOP
app equally.

## Why — the feature-flag gate

The official app switches on the deeper streams by writing a short burst of **persistent feature-flag
config values** to the strap right after the hello handshake. The most load-bearing of these is
`enable_r22_packets`; "R22" is the strap's **optical/PPG data-product packet format** (versions v1–v8),
not a hardware revision. Until those flags are set, the strap keeps the deep streams to itself.

This was reached independently three ways, which is why we trust it:

| Source | Method | What it gives |
|---|---|---|
| [judes.club — "Cracking the WHOOP 5 Bluetooth Protocol"](https://judes.club/writing/cracking-the-whoop-5-bluetooth-protocol/) + [interactive spec](https://judes.club/experiments/whoop5/) | iOS HCI capture of the official app | The full frame format + the exact 15-flag enable sequence **with values**. Our `Whoop5Config` golden test is validated byte-for-byte against its frame-builder. |
| [Asherlc/dofek](https://github.com/Asherlc/dofek/blob/main/docs/whoop-ble-protocol.md) | Android APK decompilation | The config opcodes (`0x73 START_DEVICE_CONFIG_KEY_EXCHANGE`, `0x78 SET_FF_VALUE`) and the same key names/values. |
| A community BTSnoop capture ([#103](https://github.com/ryanbr/noop/issues/103)) | Bluetooth HCI log of the official app on a real strap | Independently surfaced the same `enable_r22_*` console report + the channel layout. |

## Channel layout (5.0 / MG)

| Channel (UUID suffix on `fd4b0001-…`) | Direction | Carries | NOOP |
|---|---|---|---|
| `0x2A37` standard HR | strap → app | live heart rate | subscribed ✅ |
| `fd4b0002` | app → strap | `0xAA`-framed commands | writes here ✅ |
| `fd4b0003/4/5/7` | strap → app | `0xAA`-framed responses + data + console | subscribes to all four ✅ |

NOOP already writes commands **and** subscribes to every data channel. So the blocker is not that NOOP
isn't listening — the strap simply doesn't *start* the deep streams for a session that hasn't set the
flags.

## The frame format

Commands use the maverick/puffin envelope NOOP already implements
(`Framing.puffinCommandFrame` / `crc16Modbus` + `crc32`):

```
[0xAA][0x01][declLen u16 LE][field=0x0100][CRC16-MODBUS of the 6 header bytes]
  [inner: 0x23 type][seq][cmd][b3][payload…]
[CRC32 of inner, u32 LE]
```

- **`b3` (4th inner byte)** matters: GET_HELLO / SET_CONFIG want `0x01`; GET_DATA_RANGE /
  SEND_HISTORICAL want `0x00`. NOOP carries `b3` as the first payload byte (so `sendHistoricalData`
  with `[0x00]` is correct).
- **Write WITH RESPONSE** — write-no-response is silently dropped by the strap.

## The enable sequence (`Whoop5Config`)

One `SET_CONFIG` (cmd `0x78`) per flag; the 40-byte body is the flag name as ASCII NUL-padded to 32
bytes, the value byte (an ASCII `'1'`/`'2'`) at offset 32, then 7 zeros. The exact ordered set, with
values, is in [`Whoop5Config.swift`](../Packages/WhoopProtocol/Sources/WhoopProtocol/Whoop5Config.swift)
and [`Whoop5Config.kt`](../android/app/src/main/java/com/noop/protocol/Whoop5Config.kt), golden-tested on
both platforms. `enable_r22_packets` is the one that opens the type-`0x2F` biometric stream; the rest
tune channel selection, wear detection and sleep behaviour. Flags 1–15 come from judes.club's
frame-builder; the 16th, `enable_sig12`, was added from a real on-strap HCI capture ([#103](https://github.com/ryanbr/noop/issues/103))
that otherwise reproduced flags 1–15 byte-for-byte in this order.

## How NOOP uses it (opt-in, reversible)

- A **default-off** Settings → Experimental toggle, separate from the read-only probes because this one
  *writes* to the strap.
- A manual **"Send enable sequence to strap"** button (not auto-run on connect), enabled only when a
  5/MG is **bonded and worn** (the R22 stream is on-wrist gated).
- The 16 flags are written with-response, ~80 ms apart.
- It's **reversible** — it only changes which data the strap chooses to emit — and is the same thing the
  official app does on every connect.
- **iOS / Android only on real hardware:** macOS CoreBluetooth can't complete the authenticated SMP bond
  the command characteristic requires, so the write path is unavailable on Mac.

## Honest limits

- **No cloud scores.** Recovery/strain/sleep *scores* are computed in WHOOP's cloud and no public
  project has reproduced them. What the unlock buys is the **raw inputs** (high-rate HR, motion, fuller
  history) — which is exactly what NOOP needs, since NOOP computes its own scores on-device.
- **It may not even be necessary.** [goose #24](https://github.com/b-nnett/goose/issues/24) shows a Gen5
  band streaming type-47 history to a third-party app *without* any config write. So the first thing to
  confirm is whether a clocked 5/MG already returns deep history through the plain
  `get_data_range`/`send_historical_data` loop NOOP already runs. If it does, the write path is belt-and-
  suspenders.
- **The decode of what comes back is the next step.** Once a tester confirms deep records start arriving,
  we map the type-`0x2F` layout (documented as HR @ byte 14, accel x/y/z float32 @ 37/41/45) and feed the
  motion into NOOP's existing v25-style sleep stager.

## Why SpO₂ (and the raw respiration track) aren't available on 5.0

This is the single most common "is it broken?" report (e.g. [#623](https://github.com/ryanbr/noop/issues/623)),
so the reasoning in one place:

**It is not an encryption problem.** NOOP decodes the entire 5.0 (v18) record in plaintext — HR, R-R,
sleep, and the whole optical tail. Nothing on the wire is hidden behind a cipher NOOP would need a key
for. The barrier is that the SpO₂ data simply isn't *in* the stream in a usable form:

- **No *confirmed* SpO₂ field on the 5.0 wire — but there is now a candidate.** The raw optical tail
  (`@106` baseline, `@108/@109` amplitude pair, `@113` float) was checked against WHOOP-app SpO₂ across
  18,602 real records — it does not match; those channels track HR/motion, and there is no identifiable
  red/IR pair. Pulse oximetry fundamentally needs two wavelengths; the 5.0's decodable stream doesn't
  expose them (the v26 PPG waveform is single-channel, HR only). However, a decompile-sourced decode
  ([#103](https://github.com/ryanbr/noop/issues/103)) reads v18 byte `@82` as a **strap-computed SpO₂ %
  scalar** (tri-mode: 70–100 = real %, bit-7 = saturation sentinel, other sub-70 = diagnostic code;
  sleep-only). The evidence is currently **split**: an 8-night independent validation with real spread
  (corr +0.99, ~0.4 %/night) clears the cross-night bar, but the two nights checked on the original #103
  capture device moved *opposite* to the app value — unresolved device/firmware variance or an extraction
  error on one side. NOOP therefore decodes `@82` as `spo2_candidate_82` (deep-timeline instrumentation
  only, in-band values only) so more devices can correlate it against the app's nightly SpO₂; it does
  **not** populate `spo2Pct` or any card/score until the contradiction is resolved.
- **A calibrated % needs WHOOP's proprietary curve.** Even where raw optical exists, turning a red/IR
  ratio into a real SpO₂ % requires a device-specific calibration NOOP does not have — and NOOP will not
  fabricate one from unvalidated optical (the withdrawn #194 PPG→HR estimate is the cautionary
  precedent). `spo2Pct` is therefore nulled for *every* WHOOP; only an import writes it.

**WHOOP 4.0 differs.** The 4.0 **v24** historical layout *does* bank raw SpO₂ channels (`spo2_red@68` /
`spo2_ir@70`), so NOOP decodes the raw red/IR there (still not a calibrated %). The 5.0's v18 layout
dropped those channels — most likely SpO₂ moved to a value computed on-device / in WHOOP's cloud rather
than banked in the offload NOOP reads. NOOP reverse-engineers what the strap actually sends; if a
decodable SpO₂ isn't sent, there is nothing to decode, plaintext or not.

**Respiration is a partial exception.** The 5.0 sends no raw respiration ADC stream either (also
4.0-v24-only), so the deep-timeline *track* is empty — but respiration is still estimated on-device from
the R-R interval stream (RSA) and shown on the Health screen when enough overnight R-R is captured.

**To see SpO₂ in NOOP on a 5.0:** import it. A WHOOP data export carries `blood_oxygen_pct`, and Health
Connect import works too — both populate the Blood Oxygen card with WHOOP's own computed values.

**Could it ever change?** Only via research, not decryption — and the `@82` candidate above is exactly
that research in progress. What would flip it to a real reading: the `spo2_candidate_82` nightly values
tracking the WHOOP app's own SpO₂ across many nights on **multiple devices** (a varying signal, not one
coincidental match), including on the device where the two checked nights currently move opposite.
Until that clears the bar, SpO₂ stays import-only on the 5.0.

## Mapping the layout — ground-truth correlation

An HCI capture on its own is a pile of un-labelled bytes. The fast way to label them is *known
plaintext*: a tester's own **WHOOP data export** (app.whoop.com → Data Export) lists the official
per-night values — HRV, resting HR, skin temperature, SpO₂, respiratory rate — for exactly the nights
in the capture. Searching each record type for the byte offset + encoding that reproduces those known
values across every night pins the field without guesswork.

Two stdlib tools in [`Tools/linux-capture/`](../Tools/linux-capture/) do this:

- **`hci_extract.py`** converts a phone HCI log (iOS `.pklg` / Android `btsnoop_hci.log`) of the
  official app into the project's `capture.json` frame format — so an official-app full-sync capture
  feeds the same decoder as a Linux capture. It keeps only CRC-valid WHOOP frames.
- **`correlate_ground_truth.py`** cross-references those frames against the CSV export and reports
  candidate `(record type, offset, encoding, scale)` tuples, requiring both breadth and a
  distribution match so constants and coincidences don't score.

Crucially this is **privacy-preserving**: both tools run locally and the correlation output is only
offsets/encodings, never health values — so a 5/MG owner can contribute a confirmed field mapping to
[#103](https://github.com/ryanbr/noop/issues/103) without posting their capture or their data export.
A mapped offset still follows the project rule — *real captures, never invented offsets* — before it
lands in `parseFrameWhoop5` / `whoop_protocol.json`.

## How to help (5.0 / MG owners)

1. Update to the latest NOOP, **Settings → Experimental → "Unlock WHOOP 5/MG deep data (R22)"**.
2. With the strap **on and bonded**, tap **Send enable sequence to strap**.
3. Keep wearing it, let it sync, then **share your strap log** on [#103](https://github.com/ryanbr/noop/issues/103) — we're looking for new deep
   records (type `0x2F`) to start arriving.
4. Even better: a Bluetooth HCI capture of the **official app syncing a full night's history** shows the deep
   packets actually flowing and their layout. Method: iOS **PacketLogger** (Bluetooth diagnostic profile → `.pklg`)
   or Android **Developer Options → Bluetooth HCI snoop log** → `btsnoop_hci.log`, opened in Wireshark — the
   same iOS-HCI approach the [judes.club write-up](https://judes.club/writing/cracking-the-whoop-5-bluetooth-protocol/)
   used. Filter to just the WHOOP peripheral and attach it to [#103](https://github.com/ryanbr/noop/issues/103).

Credit to **judes.club**, **Asherlc/dofek**, and **b-nnett/goose** for the public protocol work this
builds on.

## Experimental: raw ECG / electrode channel probe

**Status:** raw-capture-only instrumentation. Strong external evidence, no on-hardware confirmation or
decode from this repo yet.

Developers in the WHOOP third-party reverse-engineering community (Discord — not this repo) report
successfully reading a WHOOP MG's real ECG waveform, raw and filtered, **without the official app**
("purely reimplemented logic"), and specifically attribute it to decoding **opcode-63 type-43 frames**
after enabling all R22 flags — quoted directly: *"For MG the opcode should be 63 to get the data
streaming for ECG and red/ir,"* and an early capture explicitly labeled *"decoded from opcode-63 type-43
frames."* They demonstrated the same channel differing between a finger held on the strap's electrode and
no contact, and described a ~30 s capture window. This is materially stronger than a single unattributed
rumor — it names the exact opcode and packet type NOOP already implements, from people who report having
gotten it working — so it is treated here as the primary lead, not one hypothesis among many.

### What's already true, independent of this report

- Opcode 63 and packet type 43 (`REALTIME_RAW_DATA`) are fully implemented and hardware-verified —
  `WhoopCommand.sendR10R11Realtime` (`Strand/BLE/Commands.swift`), decoded by the `raw_data` post-hook
  (`Packages/WhoopProtocol/Sources/WhoopProtocol/PostHooks.swift`). NOOP already knows two payload
  lengths: 1917 B (`imu`, 6-axis motion) and 1921 B (`optical`, a single AC-coupled PPG channel —
  explicitly **not** ECG, not red/IR). Both were mapped from **WHOOP 4.0** captures — MG has never been
  captured against this variant table in this repo.
- A separate, unimplemented **ECG/HeartKey command family** is documented as existing on the wire
  (`docs/PROTOCOL.md` §6, "Additional 5-class command numbers"): `ECG_MAIN_CONTROL`, `ECG_SEND_RAW`,
  `ECG_SAVE_RAW`, `ECG_SAVE_FILTERED`, `ECG_SELECT_WRIST`. **Exact opcodes are unconfirmed** — no build in
  this repo's history has ever sent them, and per the user's explicit instruction these are **not** being
  brute-forced or guessed while the opcode-63/type-43/R22 evidence above is still unexhausted.
- `DeviceFamily` cannot distinguish plain WHOOP 5.0 from 5.0/MG (only `.whoop4`/`.whoop5` exist), and the
  Add-Device wizard labels every 5-class strap `"5.0 MG"` regardless of the actual hardware. "MG-only"
  gating in NOOP therefore means "any 5/MG family connection."

### Working hypothesis

With the R22 flags set, opcode 63 returns a **third payload length** on MG hardware — an electrode/ECG
channel — that NOOP's current variant table doesn't recognize and currently discards into an "unknown"
region. Contact-gated behavior (clean waveform on contact, rails/floats otherwise) is consistent with a
capacitive or resistive contact input, similar in spirit to `skin_contact` in the historical record.

### What NOOP does about it today — staged, smallest-first

**Stage 1 (implemented): passive raw capture, no unconfirmed opcode sent.** Settings → Experimental →
"Experimental MG ECG/electrode probe" (`PuffinExperiment.ecgProbeKey`, default OFF, separate from the R22
toggle). With the R22 sequence already sent, TWO buttons — "1. Capture 30s — NO contact (baseline)" and
"2. Capture 30s — finger ON electrode" — both call `BLEManager.captureExperimentalEcgProbe(contact:)`,
which re-arms the **already-confirmed, reversible** opcode 63 for 30 seconds and logs **every** raw
type-43 frame seen during that window — unfiltered by length, undecoded — to
`<AppSupport>/OpenWhoop/puffin-ecg-probe.jsonl` (`PuffinEcgProbeLog`). Each run is tagged with a caller-
asserted `contact` label (`"on"` / `"off"`) and a `session` id, bracketed by `window_start`/`window_end`
marker lines carrying the strap state at capture time (R22 flags accepted, worn, encrypted bond) — so the
two runs can be diffed directly in the same file (by `"contact"` and `"session"`) without cross-
referencing timestamps against a separate note. Nothing is interpreted, nothing feeds a metric or score,
and nothing is shown as a waveform. This sends no opcode beyond the one already known to be safe.

**Stage 2 (not yet implemented, and not started until stage 1's evidence is exhausted): the
`ECG_MAIN_CONTROL`-family opcode probe.** If stage-1 captures show nothing beyond 1917/1921 B frames even
with contact, the next step is a small, explicit, Test-Centre-gated probe — following the same pattern as
the existing reboot (#235), extended-battery (#592), and body-location (#690) probes — that tries one
candidate opcode from the unclaimed `CommandNumber` gaps (85–95, 101–104), logs the raw
`COMMAND_RESPONSE`, and does nothing else.

### How to run the experiment (MG owners)

1. Update to the latest NOOP on **iPhone or Android** (writing to a 5/MG needs the real encrypted bond —
   a Mac can't do this).
2. **Settings → Experimental → "Unlock WHOOP 5/MG deep data (R22)"**: turn it on, then tap **"Send enable
   sequence to strap"** with the MG on and bonded. Confirm it reports accepting all 16 flags before
   continuing.
3. Turn on **"Experimental MG ECG/electrode probe"** (just below the R22 card).
4. Tap **"1. Capture 30s — NO contact (baseline)"**. Leave the strap's electrode untouched for the full
   30 seconds (rest your arm normally, don't touch the metal contact with your other hand).
5. Wait for that capture to finish (NOOP logs "window closed" and shows a frame count), then tap
   **"2. Capture 30s — finger ON electrode"**. This time, touch the strap's metal electrode with a finger
   from your OTHER hand and hold it there for the entire 30 seconds.
6. An **"Export ECG probe log…"** button appears under the two capture buttons once anything has been
   captured — tap it (share sheet on iPhone/Android, save panel + "Reveal in Finder" on macOS) and bring
   back the whole `puffin-ecg-probe.jsonl` file it produces.

### What to bring back

- The full `puffin-ecg-probe.jsonl` file (or at minimum both sessions' `window_start`/`window_end`/`frame`
  lines) — please don't hand-edit or trim it, the full byte record is what makes it useful.
- Which `session` id corresponds to which run, if not obvious from the `contact` field.
- Whatever NOOP's in-app log said when each capture started/stopped (frame counts, any error text).
- If anything about the electrode contact felt inconsistent (strap slipped, hand moved, unsure if contact
  was solid) — a noisy "on" run is still useful, just flag it.

**What matters most:** whether the `"len"` field on ANY frame differs between the two sessions. If the
"no contact" run is all 1917/1921-byte frames and the "on electrode" run shows a new length, that's the
first hard evidence of a new MG variant and the next step is mapping its layout. If both runs are
identical besides content (same lengths, same frame counts), that tells us opcode 63 alone isn't carrying
the electrode channel on this firmware, and stage 2 (the `ECG_MAIN_CONTROL` probe) becomes the next step.
