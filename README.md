# esys — BMW F-series coding toolkit

A from-scratch, open implementation of the parts of BMW **E-Sys** needed to code an
F-series car (target: **2017 X3 F25 LCI, NBT EVO "Y" iDrive 6 software**): connect over
ENET, read the active FDL settings of a module, show them, and write back **only the
bytes that changed** — starting with `CARPLAY_FULLSCREEN`.

- **Shared Swift core** (`EsysCore`): protocol stack + coding engine, compiles for
  macOS *and* iOS (same TCP code path via Network.framework).
- **CLI** (`esys`) and a **SwiftUI GUI** (`EsysApp`) on top of the same core —
  the GUI runs on the Mac and on iPhone/iPad from one codebase.
- **A virtual BMW** (`MockCar`) runs the documented protocol in-process, so the whole
  stack is testable without touching a real car.

## Status

| Capability | State |
|---|---|
| HSFZ protocol (TCP 6801 to the ZGW) | ✅ implemented + tested against captured traffic |
| Vehicle discovery (UDP 6811 broadcast) | ✅ implemented |
| UDS client (sessions, RDBI/WDBI, 0x27, 0x78 pending, echo matching) | ✅ implemented |
| Read VIN / FA / I-Step from the gateway | ✅ implemented |
| SVT scan (find ECUs + names + SVK/CAFD) | ✅ implemented |
| FDL coding read → JSON backup, diff, restore | ✅ implemented |
| Cheat-sheet import (FDLCodes.xml format) | ✅ implemented |
| CAFD parsing (decrypted CAFD XML, gzip, names TSV) | ✅ implemented — `esys cafd` |
| PSdZData folder / `.caf` file probing + UCL (NRV2B/D/E) + NCD | ✅ implemented |
| Coding write with security unlock + verify | ✅ engine done — works vs. virtual car |
| HU_NBT security seed/key algorithm | ⚠️ **open** — the one blocker for real-car writes |
| CARPLAY_FULLSCREEN offsets for your CAFD | ⚠️ **open** — needs decrypted CAFD + names entry for your iStep |
| GUI / iOS app | ✅ v1 — SwiftUI app (Mac + iPhone/iPad) over `EsysCore` |

All 43 unit/integration tests pass, including a full end-to-end run against the
virtual car (`swift test`, see `Tests/EsysCoreTests/MockCarEndToEndTests.swift`)
and UCL round-trip tests against an encoder ported from the UCL 1.03 reference
compressor.

## Quick start

```bash
swift build
swift test
swift run esys demo      # full workflow against the virtual car — no hardware needed
swift run esys help
```

Against the real car (read-only steps are safe):

```bash
swift run esys discover                      # find the car on 169.254.x.x
swift run esys scan --host 169.254.9.103     # VIN, I-Step, list of modules
swift run esys read --host 169.254.9.103 --ecu 63 --out hu_backup.json
```

Guided walkthrough for the target car (ENET cable + USB-C Ethernet adapter):
see **`Docs/FIRST_CONTACT.md`**.

Working with coding data files (no car needed):

```bash
swift run esys cafd <cafd.xml> carplay --names <names.tsv> --series F025
                              # search a CAFD for parameters; join a backup
                              # with --backup to see current values
swift run esys psdz <PSdZData> --cafd 0000F07
                              # locate a CAFD in a PSdZData folder and probe
                              # which format layer it is in (XML / gzip / UCL /
                              # PSdZ-encrypted)
swift run esys ncd <file.ncd> # read an E-Sys .ncd coding file
```

Current PSdZData `.caf` files are PsdZ-encrypted (only BMW's own library in
E-Sys decrypts them); `esys` consumes the decrypted **CAFD XML** the community
tooling produces — see `Docs/PROTOCOL.md` §6 for the full story and sources.

## GUI app (Mac + iPhone)

The same `EsysCore` powers a SwiftUI app with three tabs:

- **Car** — one-click virtual-car demo (full connect → scan → read → write flow),
  or Discover / Connect & Scan against the real car, live module list with
  SVK/CAFD ids, per-module coding read.
- **Coding** — the backup browser (sections + hex preview), cheat-sheet import
  (`FDLCodes.xml`) with current-value decode and already-active detection,
  apply with verify, restore, backup save/load (JSON, CLI-compatible).
- **CAFD** — open a decrypted CAFD XML (gzip ok) plus a community names TSV,
  resolve coding rules for your series, search every parameter, see the
  current value joined against the backup, queue and apply changes.

On the Mac:

```bash
swift run EsysApp            # straight from the package
Scripts/make-mac-app.sh      # or build a double-clickable build/EsysApp.app
```

On iPhone/iPad: open `Apps/EsysApp.xcodeproj` in Xcode, set your team under
Signing & Capabilities (CI builds use no code signing), and run it on a device.
Connect the car with an ENET cable into an Apple USB-C Ethernet adapter (or a
WiFi ENET bridge) — iOS asks once for local-network permission. The demo car
also works in the simulator with no hardware at all.

Hardware: an **ENET cable** into a USB-C Ethernet adapter on the Mac (and on
iPhone via an Apple Lightning/USB-C Ethernet adapter, or a WiFi ENET bridge
dongle — both confirmed by BimmerCode's adapter matrix).

## Repository layout

```
Sources/EsysCore/   protocol + coding engine (shared by Mac and iOS)
Sources/EsysCLI/    command line tool
Sources/EsysApp/    SwiftUI GUI (one codebase, Mac + iPhone)
Apps/               Xcode project for the iOS app (+ its Info.plist)
Scripts/            make-mac-app.sh — Mac .app bundler
Tests/EsysCoreTests unit + end-to-end tests (virtual car)
Docs/               plan, protocol research, parameters, safety
```

- `Docs/PROTOCOL.md` — everything reverse-engineered, with sources
- `Docs/PLAN.md` — the roadmap and what remains
- `Docs/PARAMETERS.md` — the CARPLAY_FULLSCREEN parameter and cheat sheets
- `Docs/SAFETY.md` — read this before writing to a real car

## Warning

This is an independent implementation of BMW's diagnostic protocols for personal
use on your own vehicle. Writing coding data can, in the worst case, put a module
in a state only a dealer can recover. The write path is gated on backups and
verification, and flashing (TAL) is explicitly out of scope. See `Docs/SAFETY.md`.
