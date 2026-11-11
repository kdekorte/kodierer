import Foundation
import EsysCore

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
let options = parseOptions(Array(arguments.dropFirst()))

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
    exit(1)
}

func parseOptions(_ args: [String]) -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg.hasPrefix("--") {
            let key = String(arg.dropFirst(2))
            if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                options[key] = args[index + 1]
                index += 2
            } else {
                options[key] = "1"
                index += 1
            }
        } else {
            index += 1
        }
    }
    return options
}

func parseECU(_ text: String) -> UInt8? {
    if text.hasPrefix("0x") || text.hasPrefix("0X") {
        return UInt8(text.dropFirst(2), radix: 16)
    }
    if text.allSatisfy({ $0.isHexDigit }) && text.count <= 2 {
        return UInt8(text, radix: 16)
    }
    return UInt8(text, radix: 10)
}

switch command {
case "version":
    print("esys 0.1.0 — BMW F-series coding toolkit (E-Sys alternative, work in progress)")

case "help", "--help", "-h":
    print("""
    esys — BMW F-series coding toolkit

    USAGE:
      esys interface                          show network interfaces + ENET link check
      esys discover [--timeout 2]            find cars on the link-local network (UDP 6811 + probe)
      esys scan --host <ip> [--dwell 0.25]   connect, read VIN/I-Step, list ECUs (SVT)
      esys read --host <ip> [--ecu 63] [--out file.json]
                                             read an ECU's coding data into a backup
      esys diff <a.json> <b.json>            byte-level diff of two coding backups
      esys cheat --file <FDLCodes.xml> [--cafd HU_NBT]
                                             list coding options from a cheat sheet
      esys cafd <file> [search] [--names <n.tsv>] [--series F025] [--backup <b.json>]
                                             inspect a CAFD: sections, parameters, values
      esys psdz <folder> [--cafd 00000F07]  locate + probe CAFD files in a PSdZData folder
      esys ncd <file.ncd> [--out b.json] [--ecu 63]
                                             read an E-Sys .ncd coding data file
      esys demo                              full workflow against the virtual car (no real car)
      esys version

    SAFETY: writes to a real car require a backup (esys read) and the HU_NBT
    security algorithm, which is not implemented yet — see Docs/PROTOCOL.md.
    """)

case "interface":
    let interfaces = NetworkInterfaces.list().filter { !$0.ipv4.isEmpty }
    for interface in interfaces {
        let mark = interface.hasLinkLocal ? "  <- link-local (ENET link looks up)" : ""
        print("\(interface.name): \(interface.ipv4.joined(separator: ", "))\(mark)")
    }
    if NetworkInterfaces.linkLocalAddresses().isEmpty {
        print("""
        no 169.254.x.x address yet.
          1. plug the ENET cable into the car (ignition on) and the adapter into the Mac
          2. System Settings > Network > (the USB/Lightning Ethernet adapter) > "Using DHCP"
          3. wait ~30 s — macOS shows "Self-Assigned IP" when it picks 169.254.x.x, that is GOOD
          4. run this again, then `esys discover`
        """)
    } else {
        print("link-local address present — run `esys discover` next")
    }

case "discover":
    let timeout = Double(options["timeout"] ?? "") ?? 2.0
    print("searching for BMWs (broadcast UDP 6811)…")
    let cars = await HSFZDiscovery.findCars(timeout: timeout)
    if cars.isEmpty {
        print("no car answered the broadcast; probing known gateway addresses…")
        let hosts = await HSFZDiscovery.probeCandidates()
        if hosts.isEmpty {
            print("none found. Plug in the ENET cable, set the Mac interface to " +
                  "link-local/DHCP, and make sure the ignition is on.")
        } else {
            for host in hosts { print("gateway candidate: \(host) (TCP 6801 open)") }
        }
    } else {
        for car in cars {
            let gateway = car.gatewayAddress.map { String(format: "0x%02X", $0) } ?? "?"
            print("found car at \(car.host) — gateway \(gateway), VIN \(car.vin ?? "?")")
        }
    }

case "scan":
    guard let host = options["host"] else { fail("missing --host (the car's IP, e.g. 169.254.9.103)") }
    let dwell = Double(options["dwell"] ?? "") ?? 0.25
    let connection = HSFZConnection()
    connection.trace = { print("  " + $0) }
    do {
        try await connection.connect(to: host)
    } catch {
        fail("\(error)")
    }
    let session = VehicleSession(transport: connection)
    let identity = await session.readIdentity()
    print("VIN: \(identity.vin ?? "?")")
    print("I-Step: \(identity.iStepText.joined(separator: " / "))")
    print("scanning addresses (this takes a while on a real car)…")
    let modules = await session.scanSVT(dwell: dwell)
    print("\n\(modules.count) modules:")
    for module in modules {
        let cafd = module.svk?.primaryCAFD.map { " CAFD \($0.fileName)" } ?? ""
        print("  \(module.displayName)\(cafd)")
    }
    connection.close()

case "read":
    guard let host = options["host"] else { fail("missing --host") }
    let ecuText = options["ecu"] ?? "63"
    guard let ecu = parseECU(ecuText) else { fail("cannot parse ECU address '\(ecuText)'") }
    let connection = HSFZConnection()
    do {
        try await connection.connect(to: host)
    } catch {
        fail("\(error)")
    }
    let session = VehicleSession(transport: connection)
    let identity = await session.readIdentity()
    print("VIN: \(identity.vin ?? "?") — reading coding of ECU 0x\(String(ecu, radix: 16))…")
    do {
        let backup = try await session.readCoding(ecu: ecu) { did in
            print(String(format: "  read section %04X", did))
        }
        print("\(backup.sections.count) sections, \(backup.sections.reduce(0) { $0 + $1.bytes.count }) bytes")
        if let svkHex = backup.svkHex, let svkBytes = Bytes.fromHex(svkHex) {
            let svk = SVK.parse(svkBytes)
            if let cafd = svk.primaryCAFD {
                print("CAFD in this module: \(cafd.fileName)  (report this — it pins the parameter data)")
            } else {
                print("SVK: \(svkHex)  (no CAFD entry recognized — please report)")
            }
        }
        let out = options["out"]
            ?? "coding_\(identity.vin ?? "car")_0x\(String(ecu, radix: 16))_\(Int(Date().timeIntervalSince1970)).json"
        let url = URL(fileURLWithPath: out)
        try backup.save(to: url)
        print("backup saved: \(url.path)")
        print("KEEP THIS FILE — it is the restore point for this ECU.")
    } catch {
        fail("\(error)")
    }
    connection.close()

case "diff":
    guard arguments.count >= 3 else { fail("usage: esys diff <a.json> <b.json>") }
    do {
        let a = try CodingBackup.load(from: URL(fileURLWithPath: arguments[1]))
        let b = try CodingBackup.load(from: URL(fileURLWithPath: arguments[2]))
        let diffs = a.diff(to: b)
        print(diffs.isEmpty ? "identical" : describeDiffs(diffs))
    } catch {
        fail("\(error)")
    }

case "cheat":
    guard let file = options["file"] else { fail("missing --file (a cheat sheet XML)") }
    do {
        let sheet = try CheatSheet.parse(url: URL(fileURLWithPath: file))
        let cafdName = options["cafd"]
        let cafdID = options["cafd-id"]
        let codes = sheet.codes(cafdID: cafdID, ecuName: cafdName)
        guard !codes.isEmpty else { fail("no matching codes in \(file)") }
        for code in codes {
            print("• \(code.description)  [\(code.cafdName ?? code.cafdID ?? "?")]")
            for op in code.operations {
                print("    section \(String(format: "%04X", op.group)) byte \(op.start)\(op.start == op.end ? "" : "...\(op.end)")" +
                      " mask \(String(op.mask, radix: 2)) = \(op.value)")
            }
        }
        print("\n\(codes.count) options. Apply one with the app once the write path is enabled.")
    } catch {
        fail("\(error)")
    }

case "cafd": {
    let positional = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard let path = positional.first else {
        fail("usage: esys cafd <file> [search] [--names <n.tsv>] [--series F025] [--backup <b.json>] [--all]")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let probe = CAFDProbe.probe(data: data, series: options["series"])
        print("\(path): \(probe.kind.rawValue)" + (probe.detail.isEmpty ? "" : " — \(probe.detail)"))
        guard let cafd = probe.cafd else {
            fail("cannot parse this file as CAFD data (see the note above)")
        }
        var names: CAFDNames?
        if let namesPath = options["names"] {
            names = try CAFDNames.parse(url: URL(fileURLWithPath: namesPath))
        }
        var backup: CodingBackup?
        if let backupPath = options["backup"] {
            backup = try CodingBackup.load(from: URL(fileURLWithPath: backupPath))
        }
        let cafdID = SWEFileName.parse(URL(fileURLWithPath: path).lastPathComponent)
            .map { String(format: "%08X", $0.id) }
        let showAll = options["all"] != nil
        let search = showAll ? "*" : (options["search"] ?? positional.dropFirst().first)?.lowercased()

        print("\(cafd.datagroups.count) datagroups, \(cafd.functionCount) functions"
              + (cafd.mainSeries.isEmpty ? "" : ", series: " + cafd.mainSeries.joined(separator: ", "))
              + (search == nil ? " — pass a search term (or --all) to list parameters" : ""))
        for dg in cafd.datagroups {
            let groupName = names?.groupName(datagroup: dg, cafdID: cafdID)
            if let search, search != "*" {
                let haystack = ((groupName ?? "") + " " + dg.functions.map {
                    names?.functionName(datagroup: dg, function: $0, cafdID: cafdID) ?? $0.placeholderName
                }.joined(separator: " ")).lowercased()
                guard haystack.contains(search) else { continue }
            }
            print(String(format: "datagroup %04X", dg.address)
                  + " (\(dg.datagroupClass ?? "?"), \(dg.functions.count) functions)"
                  + (groupName.map { " — \($0)" } ?? ""))
            guard search != nil else { continue }
            for fn in dg.functions {
                let name = names?.functionName(datagroup: dg, function: fn, cafdID: cafdID)
                    ?? fn.placeholderName
                if let search, search != "*", !name.lowercased().contains(search),
                   !(groupName ?? "").lowercased().contains(search) { continue }
                var line = "  byte \(fn.start)\(fn.start == fn.end ? "" : "-\(fn.end)")"
                    + "  mask \(fn.maskText ?? "-")  \(name)"
                if let backup, let section = backup.section(dg.address),
                   let current = CAFD.maskedHex(sectionBytes: section.bytes, function: fn) {
                    line += "  = \(current)"
                    if let match = cafd.currentValue(of: fn, in: dg, backup: backup) {
                        line += match.isDefault ? "  [default]" : "  [wert_\(match.index + 1)]"
                    }
                }
                print(line)
                for value in fn.values {
                    let valueName = names?.valueName(datagroup: dg, function: fn, value: value, cafdID: cafdID)
                    var text = String(format: "      wert_%02d  %@", value.index + 1, value.hex)
                    if value.isDefault { text += "  [default]" }
                    if let valueName, !valueName.isEmpty { text += "  \(valueName)" }
                    if case .applicable(let rule) = value.rule {
                        let short = rule.text.count > 56 ? String(rule.text.prefix(56)) + "…" : rule.text
                        text += "  [\(short)]"
                    }
                    print(text)
                }
            }
        }
    } catch {
        fail("\(error)")
    }
}()

case "psdz": {
    let positional = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard let folder = positional.first else {
        fail("usage: esys psdz <PSdZData folder> [--cafd 00000F07] [--series F025]")
    }
    let store = PSdZDataStore(path: folder)
    guard let sweRoot = store.sweRoot else {
        fail("no swe/ folder under '\(folder)' — point this at the PSdZData folder (or its parent)")
    }
    print("PSdZData: \(sweRoot.path)")
    if let cafdText = options["cafd"] {
        let text = cafdText.hasPrefix("0x") ? String(cafdText.dropFirst(2)) : cafdText
        guard let id = UInt32(text, radix: 16) ?? UInt32(text) else {
            fail("--cafd must be a hex id like 00000F07 (from `esys read`'s SVK report)")
        }
        let files = store.files(kind: "cafd", id: id)
        guard !files.isEmpty else {
            fail("no CAFD \(String(format: "%08X", id)) in this PSdZData — check the SVK id first")
        }
        for (name, url) in files {
            let data = (try? Data(contentsOf: url)) ?? Data()
            let probe = CAFDProbe.probe(data: data, series: options["series"])
            print("\(name.fileName): \(probe.kind.rawValue)"
                  + (probe.detail.isEmpty ? "" : " — \(probe.detail)"))
            if let cafd = probe.cafd {
                print("    \(cafd.datagroups.count) datagroups, \(cafd.functionCount) functions"
                      + " — inspect with: esys cafd \"\(url.path)\"")
            }
        }
    } else {
        for kind in PSdZDataStore.kinds {
            let count = store.files(kind: kind).count
            if count > 0 { print("  \(kind): \(count) files") }
        }
        print("inspect one CAFD with: esys psdz <folder> --cafd <id from the SVK>")
    }
}()

case "ncd": {
    let positional = arguments.dropFirst().filter { !$0.hasPrefix("--") }
    guard let path = positional.first else {
        fail("usage: esys ncd <file.ncd> [--out backup.json] [--ecu 63]")
    }
    do {
        let ncd = try NCD.parse(url: URL(fileURLWithPath: path))
        if let id = ncd.cafdID {
            print("CAFD \(String(format: "%08X", id))"
                  + (ncd.version.map { String(format: " version %03d_%03d_%03d", $0.main, $0.sub, $0.patch) } ?? ""))
        } else {
            print("no S0 header — sections only")
        }
        for section in ncd.sections {
            print(String(format: "  section %04X: %d bytes", section.did, section.bytes.count))
        }
        if let out = options["out"] {
            let ecuText = options["ecu"] ?? "63"
            let ecu = Int(ecuText, radix: 16) ?? Int(ecuText) ?? 0x63
            try ncd.backup(ecuAddress: ecu).save(to: URL(fileURLWithPath: out))
            print("saved backup to \(out) (ECU 0x\(String(ecu, radix: 16)))")
        }
    } catch {
        fail("\(error)")
    }
}()

case "demo":
    print("=== esys demo: virtual F25, no real car involved ===\n")
    let car = MockCar()
    do {
        try await car.start()
    } catch {
        fail("cannot start virtual car: \(error)")
    }
    defer { car.stop() }
    print("virtual car listening on 127.0.0.1:\(car.port) (VIN \(car.vin), HU_NBT at 0x63)")

    let connection = HSFZConnection()
    do {
        try await connection.connect(to: "127.0.0.1", port: car.port)
    } catch {
        fail("cannot connect to virtual car: \(error)")
    }
    defer { connection.close() }
    let session = VehicleSession(transport: connection)

    // 1. Identify
    let identity = await session.readIdentity()
    print("1. identity — VIN \(identity.vin ?? "?"), I-Step \(identity.iStepText.first ?? "?")")

    // 2. Scan
    let modules = await session.scanSVT(range: 0x10...0x70, dwell: 0.1)
    print("2. SVT scan — \(modules.count) modules: " + modules.map(\.displayName).joined(separator: ", "))

    // 3. Read coding with backup
    let backup = try await session.readCoding(ecu: car.huNBTAddress, ecuName: "HU_NBT")
    print("3. read HU_NBT coding — \(backup.sections.count) sections, " +
          "\(backup.sections.reduce(0) { $0 + $1.bytes.count }) bytes (backup kept in memory)")

    // 4. Apply the demo edit (like a cheat-sheet CarPlay toggle)
    let before = car.codingBytes(did: 0x3000)![96]
    let modified = try await session.applyOperations([MockCar.demoOperation()], to: backup,
                                                      description: "demo bit",
                                                      security: MockCarAlgorithm())
    let after = car.codingBytes(did: 0x3000)![96]
    print("4. applied demo edit — section 0x3000 byte 96: \(String(before, radix: 16)) -> " +
          String(after, radix: 16) + " (security unlocked, verified by re-read)")

    // 5. Diff
    print("5. diff old -> new:\n   " + describeDiffs(backup.diff(to: modified))
        .replacingOccurrences(of: "\n", with: "\n   "))

    // 6. Restore
    try await session.restore(backup, security: MockCarAlgorithm())
    let backToOriginal = car.codingBytes(did: 0x3000)![96] == before
    print("6. restore from backup — byte 96 back to \(String(car.codingBytes(did: 0x3000)![96], radix: 16)): " +
          (backToOriginal ? "OK" : "FAILED"))
    print("\ndemo complete — the same flow against a real car needs: ENET cable, " +
          "the real HU_NBT security algorithm (Docs/PROTOCOL.md), and a verified cheat entry.")

default:
    fail("unknown command '\(command)' — try `esys help`")
}
