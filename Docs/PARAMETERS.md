# Parameters — CARPLAY_FULLSCREEN and cheat sheets

## The target parameter

`CARPLAY_FULLSCREEN` is an FDL argument of the **HU_NBT** module (the NBT EVO
head unit) on iDrive 6 cars with the "Y"-series software (2017+). Setting it
from `nicht_aktiv` to `aktiv` makes CarPlay use the full 10.25" screen instead
of the boxed 2/3 view.

What we know:

- It lives in one of the HU_NBT coding sections (3000–3015 range, most likely
  3000/3002), at a byte/bit offset that is **specific to the CAFD version**
  (= your iStep). ✅ community consensus, ⚠️ exact offset not yet pinned for a
  Y-series CAFD.
- The community publishes it in cheat sheets; the classic collections
  (Almaretto, Bundang_Thunder, ...) predate ID6 and do **not** contain it —
  the ID6-era sheets are distributed via forums and E-Sys MAX.

## How the app will get the offsets

1. **Cheat-sheet import** (implemented): `CheatSheet.swift` parses the
   FDLCodes.xml format (`<cafd>/<code>/<group>/<function start end mask>`).
   Drop a sheet covering your CAFD into the app and the option appears with
   its exact byte edits. `kodierer cheat --file <sheet.xml> --cafd HU_NBT` lists it.
2. **One-time calibration** (planned): `kodierer read` before and after making the
   change once with E-Sys; `kodierer diff` shows the changed byte. That offset can
   then be saved as a named parameter in the app's registry — after that, the
   app never needs E-Sys again.
3. **CAFD parsing** (later): read parameter definitions straight from PSdZData.

## Built-in registry (status)

The registry format is ready (`FDLOperation`: section + byte offset + mask +
value). No real offsets are hard-coded yet — deliberately, because a wrong
offset written to a real head unit is exactly the kind of damage this project
exists to avoid. The demo parameter (`MockCar.demoOperation()`, section 3000
byte 96 bit 0x10) is **synthetic test data**, not a real CarPlay offset.

## Value semantics

FDL values are bits: `aktiv`/`nicht_aktiv` map to 1/0 for masked fields;
numeric values in cheat sheets are decimal ("32") or bare hex ("0B"). Enum-like
symbols ("TFL_S", emblem numbers) need CAFD data to resolve — the engine
reports them as unresolved rather than guessing.
