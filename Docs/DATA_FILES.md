# Data files

Kodierer reads community coding data from a `Data/` folder. On macOS
(`swift run Kodierer` from the repo) that is `<repo>/Data/`; a packaged app
would bundle it as `Resources/Data`. Everything is optional — files that fail
to parse are skipped silently.

| Folder | Contents | Source |
|---|---|---|
| `Data/names/*.tsv` | Community parameter names, merged if several files. | OpenCAFDMap `names/*.tsv` (CC0) |
| `Data/options/*.tsv` | Plain-language option descriptions keyed by function name (`NAME\tDESCRIPTION\tCATEGORY\tMODULE\tSECTION`). Gives the option tree its readable text and a category fallback. | curated from F10/F25/F30 cheat-sheet PDFs — see `Data/options/f25-cheatsheet.tsv` |
| `Data/cafds/` | Decrypted CAFD XML for one ECU, plain or gzip (`.xml`, `.xml.gz`). The first parseable file is loaded. | OpenCAFDMap decrypted cache; E-Sys via the PsdZ library |
| `Data/cheats/*.xml` | FDLCodes-style cheat sheets (`<CAFD>` blocks with codes). | FDLCodes.xml community exports |
| `Data/backups/*.json` | Saved coding backups. The newest is loaded as the current snapshot. | This app's "Save…" |

## Names TSV format

OpenCAFDMap's 8 columns, plus an optional 9th `CATEGORY` column that groups
options BimmerCode-style (Media, Comfort, Display, Lighting, …). Functions
without a category fall back to the datagroup name, then `Section XXXX`.

```
# CAFD_ID  ADDRESS  START  END  MASK  VALUE_HEX  NAME             COMMENT      CATEGORY
ANY        3000     96     96   16               CARPLAY_FULLSCREEN  demo     Media
ANY        3000     96     96   16    00         Not fullscreen               Media
ANY        3000     96     96   16    10         Fullscreen                  Media
```

- Rows with an empty start/end name the datagroup (used as the fallback
  category).
- Rows with an empty value hex name the function.
- Rows with a value hex name that value (the choices shown in the UI).

## What cannot be loaded directly

PSdZData `.caf` files as shipped are encrypted; only BMW's PsdZ library
(inside E-Sys) decrypts them. Use the decrypted XML form (OpenCAFDMap's cache)
— or run `kodierer-cli psdz <folder>` to check what a file contains.
