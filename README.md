# esys — BMW F-series coding toolkit

A from-scratch, open implementation of the parts of BMW **E-Sys** needed to code an
F-series car (target: **2017 X3 F25 LCI, NBT EVO "Y" iDrive 6 software**): connect over
ENET, read the active FDL settings of a module, show them, and write back **only the
bytes that changed** — starting with `CARPLAY_FULLSCREEN`.

- **Shared Swift core** (`EsysCore`): protocol stack + coding engine, compiles for
  macOS *and* iOS (same TCP code path via Network.framework).
- **CLI** (`esys`) for the Mac first; a GUI app and the iPhone app come later on top
  of the same core.
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
| Coding write with security unlock + verify | ✅ engine done — works vs. virtual car |
| HU_NBT security seed/key algorithm | ⚠️ **open** — the one blocker for real-car writes |
| CARPLAY_FULLSCREEN offsets for your CAFD | ⚠️ **open** — needs cheat entry for your iStep |
| GUI / iOS app | planned |

All 22 unit/integration tests pass, including a full end-to-end run against the
virtual car (`swift test`, see `Tests/EsysCoreTests/MockCarEndToEndTests.swift`).

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

Hardware: an **ENET cable** into a USB-C Ethernet adapter on the Mac (and later,
per BimmerCode's own docs, the same works with an Apple Lightning/USB-C Ethernet
adapter on iPhone, or a WiFi ENET bridge dongle).

## Repository layout

```
Sources/EsysCore/   protocol + coding engine (shared by Mac and iOS)
Sources/EsysCLI/    command line tool
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
