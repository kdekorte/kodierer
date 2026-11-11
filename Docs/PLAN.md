# Plan

Goal: a Mac + iPhone app that replaces E-Sys for FDL coding on the user's 2017
BMW X3 (F25 LCI, NBT EVO ID6 "Y" software) — read active settings, change them
safely, write back only what changed. First concrete target: `CARPLAY_FULLSCREEN`.

## Phase 0 — research (done)

Wire protocol fully mapped from open-source implementations and captured
traffic; see `Docs/PROTOCOL.md`. One open item: the HU_NBT security algorithm.

## Phase 1 — core + CLI, read path (done)

- [x] HSFZ framing + TCP client with ack skipping, reply matching, 0x78 pending
- [x] Vehicle discovery (UDP 6811) + candidate probing
- [x] UDS layer (sessions, RDBI/WDBI, security access plumbing)
- [x] Identity reads (VIN, FA, I-Step) and SVT scan
- [x] FDL coding read → JSON backup, byte diff, restore
- [x] Cheat-sheet import (FDLCodes.xml) and mask/offset edit engine
- [x] Virtual car (MockCar) + end-to-end tests (22/22 passing)
- [x] Write engine incl. security unlock and verify — proven against MockCar

## Phase 2 — first contact with the real car (next)

Read-only, zero risk:

1. Get an ENET cable, plug into the X3, Mac interface to DHCP/link-local.
2. `esys discover` → find the ZGW; confirm VIN.
3. `esys scan` → verify HU_NBT address (expected 0x63) and read its SVK; record
   the CAFD id/version and the I-Step.
4. `esys read --ecu 63` → full coding backup of the head unit. **Keep it.**
5. Optional: read a second module (KOMBI) to validate the flow.

Deliverable: a real backup file + the exact CAFD/iStep identity of the car.

## Phase 3 — closing the two open items

- **Security algorithm**: derive the HU_NBT seed/key (see PROTOCOL.md §5 —
  PSdZData SGBD analysis or one captured E-Sys session). Then re-run the
  MockCar-style workflow against the real HU with a harmless byte first.
- **CARPLAY_FULLSCREEN offsets**: find a cheat-sheet entry for the exact CAFD
  (Y-series ID6), or derive by diffing a before/after E-Sys change once, then
  hard-code it as a first-class parameter (see PARAMETERS.md).

## Phase 4 — GUI apps

- macOS app (SwiftUI) over `EsysCore`: connect wizard, module list, settings
  browser (from cheat sheets + eventually CAFD parsing), one-click toggles,
  backup management, restore button.
- iOS app: same core; ENET via Apple USB-C/Lightning Ethernet adapter or a WiFi
  ENET bridge (both confirmed working by BimmerCode's adapter matrix).

## Phase 5 — "all the settings"

- CAFD parsing (PSdZData) to enumerate every parameter with names/choices
  instead of relying on cheat sheets; symbolic value resolution (aktiv /
  nicht_aktiv / enums) from the CAFD itself.
- E-Sys Launcher cheat format import (superset of FDLCodes.xml).
- Optional: FA read/write, more modules, G-series DoIP (codec exists).

## Out of scope (deliberately)

- Flashing / TAL / programming (too risky, no benefit for coding).
- Anything that writes without a verified backup.
