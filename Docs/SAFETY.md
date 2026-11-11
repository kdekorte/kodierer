# Safety

Rules this project enforces, and rules for you.

## What the code enforces

1. **Backups first.** `readCoding` snapshots every section to JSON before any
   write; `VehicleSession.applyOperations` writes only the sections that
   actually differ, then **re-reads and verifies** them.
2. **Restore path always available.** `CodingEngine.restore` writes a whole
   backup back, section by section.
3. **Idempotence.** Applying a setting that is already active is a no-op — no
   write happens.
4. **No guessing.** Symbolic FDL values that cannot be resolved without CAFD
   data fail loudly instead of writing zeros.
5. **Security gate.** Writes fail with an explicit error until a real seed/key
   algorithm is present — we never blind-write to a locked module.
6. **No flashing.** RequestDownload/TransferData (TAL) are not implemented and
   will not be.

## What you must do on a real car

- **Ignition on, engine off**, parking brake set, no gear engaged.
- **Stable power**: battery charger recommended; modules must not lose power
  mid-write. Low voltage aborts are a real failure mode.
- **One connection at a time** — E-Sys, ISTA and this tool fight over the
   single tester slot the ZGW grants.
- **Keep the backup JSON files** somewhere safe (they are the only restore
  point short of a dealer visit). Export them; don't rely on one Mac.
- After coding, expect the head unit to **reboot itself**; give it a minute.
- Never write to a module whose backup you don't have for **that exact
  software state** (after a dealer update, take a fresh backup).
- If a write fails midway: do not panic-retry randomly. Re-read the module,
  compare against the backup, restore the affected sections.

## Legal

Independent hobbyist tool for your own vehicle. BMW, E-Sys, ISTA, CarPlay are
trademarks of their owners; this project is not affiliated with or endorsed by
BMW AG. Protocol data in `Docs/PROTOCOL.md` comes from public open-source
projects and published traffic captures.
