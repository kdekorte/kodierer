# First contact with the X3 (read-only walkthrough)

You have: ENET cable + USB-C Ethernet adapter on the Mac. This walkthrough only
**reads** — discovery, module list, and a full backup of the head unit's coding.
Nothing is written to the car.

## 0. Build the tool

```bash
cd ~/projects/kodierer
swift build
```

## 1. Prepare the car

- Ignition **on** (press Start twice without touching the brake), **engine off**.
- Parking brake on, selector in P, lights/heating off, doors can stay closed.
- No other diagnostic app connected (E-Sys/ISTA/BimmerCode must be closed).

## 2. Plug in and check the link

ENET cable into the OBD port (driver footwell), adapter into the Mac.

- System Settings → Network → select the Ethernet adapter → **Using DHCP**.
- After ~30 s it shows **"Self-Assigned IP"** with a 169.254.x.x address —
  that is exactly what we want, not an error.

```bash
swift run kodierer interface
```

Look for a line like `en5: 169.254.42.7  <- link-local (ENET link looks up)`.
If nothing: reseat the cable at the OBD port, try the other way around, wait
another 30 s, run again.

## 3. Find the car

```bash
swift run kodierer discover
```

Expected: `found car at 169.254.x.x — gateway 0x10, VIN WBA...`.
(The tool broadcasts on UDP 6811, sweeps your subnet, and probes known gateway
addresses.) If several cars are nearby (garage), pick yours by VIN.

## 4. Confirm identity and find the head unit

```bash
swift run kodierer scan --host 169.254.x.x
```

Check:

- the **VIN** matches your car,
- **HU_NBT [0x63]** appears in the module list (this confirms the head unit
  address for all future steps),
- the I-Step line (e.g. `F025-17-11-503`) — your software level,
- the CAFD shown next to HU_NBT, e.g. `CAFD_00000F07_013_001_009`.

The scan walks all addresses with a short timeout, so it takes a minute or two.

## 5. Back up the head unit coding

```bash
swift run kodierer read --host 169.254.x.x --ecu 63 --out F25_HU_NBT_backup.json
```

This reads every coding section of the head unit into one JSON file. **Store it
somewhere safe** (and keep every future backup). It is the restore point if a
coding operation ever goes wrong, and it documents your exact software state.

## 6. Report back (so we can finish the CarPlay parameter)

Copy the output of steps 4 and 5 and send:

- HU_NBT address and the CAFD line,
- the I-Step,
- the list of sections that were read,
- whether the VIN/scan all looked normal.

With that we can (a) verify the SVK parsing assumptions against real data,
(b) pin the exact `CARPLAY_FULLSCREEN` offsets for your CAFD, and (c) work out
the security algorithm (PROTOCOL.md §5) so the write step can be enabled.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `kodierer interface` shows no 169.254 address | Wait longer; reseat cable; check adapter LEDs; try another USB port |
| discover finds nothing | Re-run with `--timeout 5`; check the macOS firewall allows outgoing UDP; make sure the ignition is on |
| scan lists nothing but discover worked | The ZGW granted the tester slot to someone else — close other apps, reconnect |
| read fails with "no coding sections" | Wrong ECU address — check the scan output for the actual HU_NBT address |
