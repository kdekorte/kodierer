# Protocol research — BMW F-series coding over ENET

Findings assembled 2026-11 from public open-source implementations and captured
traffic. Confidence marks: ✅ confirmed by multiple sources / real captures,
⚠️ inferred, to verify against a real car.

## 1. Network layer

- The ENET cable wires the OBD port's Ethernet pins to an RJ45. The car's central
  gateway (**ZGW**) uses **link-local addressing (169.254.0.0/16)**. Observed ZGW
  addresses: `169.254.0.2`, `169.254.9.100–105`. The Mac should use DHCP or
  link-local auto-configuration on that interface. ✅
- **HSFZ** (BMW's framing) on **TCP 6801**. One tester at a time; a second
  connection is reset. ✅
- **Vehicle search on UDP 6811**: broadcast an empty HSFZ frame with control word
  `0x0011`; the gateway replies from its own address with
  `DIAGADR<gateway hex>BMWMAC<12 hex>BWMAC...BMWVIN<17>` (sic — `BMWVIN`).
  E-Sys finds cars this way. ✅
- **F-series gateways do not answer DoIP** (ISO 13400, port 13400) — that is the
  G-series path. Our DoIP support is therefore future work only. ✅ (svietlik
  source states this explicitly.)

## 2. HSFZ framing

```
[UInt32 BE length][UInt16 BE control][src][dst][UDS payload...]
```

- `length` counts everything **after** the 6-byte header (= 2 + UDS length). ✅
- Control words: `0x0001` diagnostic data, `0x0002` gateway **ack/echo of the
  request** (client must ignore), `0x0011` identification, `0x0012` keep-alive. ✅
- Error control words: `0x40` bad tester address, `0x41` bad control word,
  `0x42` bad format, `0x43` bad destination, `0x44` too large, `0x45` diag app
  not ready, `0xFF` out of memory. ✅
- Addresses are one byte: tester `0xF4`, functional/broadcast `0xDF`, ZGW `0x10`,
  DME `0x12`, FEM `0x40`, KOMBI `0x60`, **HU_NBT 0x63** (⚠️ verify by SVT scan),
  REM `0x72`.
- Verified byte-for-byte against ISTA captures published with
  kaiwen-z/bmw-enet-tool (see `Tests/EsysCoreTests/HSFZTests.swift`).

## 3. UDS usage (what E-Sys actually does)

Standard ISO 14229 services over HSFZ, routed by the ZGW to the target address:

| Service | Use |
|---|---|
| `0x10 03` | extended session before coding |
| `0x27 11/12` | security access — **8-byte seed** ("PSdZ refuses any other length") |
| `0x22` | read DIDs: identity (`F190` VIN, `F197` ECU name, `F189/F191` versions, `F101` SVK, `F186` session), gateway/VCM (`3F06` FA, `3F09` FP, `100B` I-Step) and **coding sections** (below) |
| `0x2E` | write DIDs — this is how coding data is written |
| `0x3E 80` | TesterPresent keep-alive (functional) |
| `0x11` | ECU reset after coding (NBT reboots by itself) |

Positive responses echo SID+0x40 plus the DID/routine id; negative responses are
`7F <SID> <NRC>`; `0x78` = response pending (keep waiting). ✅

## 4. FDL coding data model

- Coding data lives in **per-section UDS DIDs**. An NCD (net coding data) block's
  memory address is `DID * 256 + offset`, and the section numbers in E-Sys,
  cheat sheets and CAFDs (3000, 3001, 3062, ...) are those DIDs **written in
  hex** — so "3062" means DID 0x3062 = 12386, and `esys` stores the numeric
  value everywhere. ✅ (kdrcoding/fake-car `Car.cs` `LoadNcd`; OpenCAFDMap
  `ocm/cod_import.py` — BimmerCode `.cod` `blockAddress` 12288 = 0x3000;
  datagroup `address` attributes in CAFD XML are the same hex block numbers.)
- Reading = `22 <DID>` per section; writing = `2E <DID> <bytes>` per section,
  after session + security. ✅ (fake-car implements exactly this to satisfy
  E-Sys.) Section discovery probes `0x3000...0x30FF` by default; the
  authoritative per-ECU list is the datagroup set of its CAFD (see §6).
- The **SVK** (DID `0xF101`) lists installed software as 8-byte entries
  (process class, 4-byte id, 3 version bytes) after a 16-byte header; the CAFD
  entry tells which coding container the module uses (`CAFD_FFFFFFFF` = erased).
  ⚠️ Entry layout inferred from fake-car; the process-class byte for CAFD is
  assumed `0x11` (constant `SVK.cafdProcessClass`, adjust after a live read).
- I-Step (DID `0x100B`, on the gateway): 3 × 8 bytes = series ("F025"), year,
  month, 2-byte counter, e.g. `F025-17-07-503`. ✅

## 5. Security access — **the open item**

- Real modules require `0x27` seed/key before `0x2E`. The key algorithm is
  ECU-specific; E-Sys computes it from SGBD data in PSdZData.
- No open-source implementation of the **HU_NBT (F-series)** algorithm was found
  in the surveyed repos (svietlik is read-only; idrive7-8-ssh-root uses
  G-series certificate auth).
- Options to close this gap (in order of preference):
  1. Derive it from the user's own PSdZData Lite (the SGBD prg files contain the
     algorithm as BEST1 bytecode — ediabaslib interprets them at runtime, GPL).
  2. Capture one E-Sys coding session with fake-car-style logging or Wireshark
     (`27 11` seed, `27 12` key pairs) and derive the transform.
  3. Community implementations for specific modules.
- The code has a pluggable `SecurityAlgorithm` protocol; until this is filled in,
  real-car writes intentionally fail with a clear error.

## 6. CAFD / PSdZData formats (researched, parser implemented)

Everything in this section is sourced from open community tools; our Swift
implementations live in `CAFD.swift`, `CAFDNames.swift`, `NCD.swift`,
`PSdZData.swift`, `UCL.swift`, `Gzip.swift`.

**PSdZData layout.** SWE files live under `psdzdata/swe/<kind>/` with names
`<kind>_<id 8 hex>.<ext>.<main>_<sub>_<patch>`, e.g.
`cafd_00000F07.caf.013_001_009`. Kinds: blup, btld, cafd, fafp, flsl, flup,
gwtb, ibad, swfk, swfl, tlrt. The KIS databases (`psdzdata/kiswb/<series>/`,
HSQLDB `.script` files) map SVT → software; `esys psdz` locates CAFDs by the
SVK id instead, so no KIS parsing is needed. (LeonB1ham/svt-psdzdata-export
`engine.py`; kdrcoding/fake-car `CarBuilder.java`.)

**The `.caf` encryption wall.** Current PSdZData CAFDs are *encrypted*; the
only known decryption is BMW's own PsdZ library inside E-Sys
(`PsdzLogic.decryptVerifyCAF`). OpenCAFDMap — the most serious community
project here — deliberately drives E-Sys's own jars (headless Nashorn,
`esys/decrypt.js`) to produce decrypted **CAFD XML** (gzip-compressed,
namespace `http://bmw.com/2005/psdz.data.caf`). No standalone open decryptor
exists. Consequence for us: `esys` parses CAFD XML (and probes `.caf` files,
telling you which layer they're in), and the PSdZData path needs either a
decrypted XML from an E-Sys machine or the community definition files.

**CAFD XML structure** (per OpenCAFDMap `ocm/build_defdb.py` `parse_cafd`):

    data → datagroup (address, datagroupClass, units)
         → function (storageInfo: start, end, size, mask)
         → condParam (bool rule + values/unitVal hex bytes)

- `datagroup@address` is the hex block number ("3000" = DID 0x3000); class is
  USER (coding) or SYSTEM (NCD signature block).
- `mask` is binary-with-b, e.g. `11111111b` = 0xFF.
- Each value ("wert_NN" in E-Sys) carries a coding rule — an XPath over
  vehicle-order criteria — with a `mainSeries` attribute; the rule matching
  the car's series decides which value applies, `isDefault` marks the factory
  default.
- **Names are trimmed to "." in modern PSdZData**; readable names come from
  community lists keyed by `cafd + address + start + end + mask`
  (OpenCAFDMap `names/*.tsv`, CC0). `CAFDNames.swift` parses that format, and
  `esys cafd <file> carplay --names <file>.tsv` is the search workflow.

**UCL compression.** PSdZData flash files (SWFL/BTLD `.bin` + `.xml` sibling)
declare per-segment `COMPRESSION-METHOD` of `gz`/`gzip` or `nrv`/`ucl` in the
XML manifest; the UCL family (NRV2B/2D/2E, bit streams u8/le16/le32 — UCL 1.03
by Markus Oberhumer, GPL-2) is what the community `unucl` tool decodes. Our
`UCL.swift` is a faithful port of the reference decompressors
(`src/n2b_d.c`, `n2d_d.c`, `n2e_d.c`, `getbit.h`), validated by round-trip
tests against an encoder ported from the reference compressor
(`src/n2_99.ch` + `ucl_mchw.ch`). Bit/byte interleaving follows the
reservation model: a bit word reserves its bytes in the output first, raw
bytes are appended while the word fills.

**NCD (E-Sys coding data files).** Motorola S-records: S0 header = CAFD id +
version, S2 records of ≤32 bytes at `blockAddress * 256 + offset`.
`NCD.swift` parses them (checksums verified) into `CodingSection`s, so
E-Sys-written `.ncd` files and fake-car car folders load as backups.

## 7. Sources

- **kaiwen-z/bmw-enet-tool-public-wenz77-on-bimmerforums** (MIT) — HSFZ framing
  in Python + real ISTA captures (used verbatim in our tests) + UDP discovery
  candidates.
- **egzey0/svietlik** (TypeScript) — HSFZ/DoIP client design, echo-based reply
  matching, "F-series gateways do not answer DoIP", UDP 6811 ident request.
- **cauliflowermossgrape/idrive7-8-ssh-root** (Python) — modern HSFZ client
  (MGU at 0x63, gateway link-local notes, response/echo handling).
- **kdrcoding/fake-car** — E-Sys-compatible car simulator; source of the
  ack-frame behavior, module/session/UDS semantics, "8-byte seed", NCD↔DID
  mapping, VCM DIDs (3F06/3F09/100B), and the overall coding flow. (Read for
  protocol understanding only; our Swift implementation is independent.)
- **uholeschak/ediabaslib** (GPL-3.0) — reference for EDIABAS/SGBD concepts;
  not copied.
- **packetpilot/bmw-f** — community cheat sheets in FDLCodes.xml format (schema
  reference for `CheatSheet.swift`).
- **shamair28/OpenCAFDMap** (MIT; names CC0) — the CAFD XML schema
  (`ocm/build_defdb.py`), the names-TSV format, the PsdZ-decryption reality
  (`esys/decrypt.js`), and the name-trimming state of modern PSdZData.
- **LeonB1ham/svt-psdzdata-export** (MIT) — PSdZData folder/file naming
  (`engine.py` SWE_NAME_RE, SWE_KIND_DIRS).
- **speidy/BMW-SWE-extractor** + **CDFN/bmw-virtual-reader** — flash-file XML
  manifests (FLASH-SEGMENT, COMPRESSION-METHOD gz/nrv) and the `unucl`/
  libucl usage that confirmed UCL as the compression family.
- **UCL 1.03** (Markus F.X.J. Oberhumer, GPL-2) — reference decompressors and
  compressor our `UCL.swift` and its tests are ported from, line for line.
- BimmerCode docs — confirmation that F/G/I-series coding works over ENET with a
  plain cable + Apple Ethernet adapter on iPhone, or WiFi ENET bridges.
