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
      esys discover [--timeout 2]            find cars on the link-local network (UDP 6811 + probe)
      esys scan --host <ip> [--dwell 0.25]   connect, read VIN/I-Step, list ECUs (SVT)
      esys read --host <ip> [--ecu 63] [--out file.json]
                                             read an ECU's coding data into a backup
      esys diff <a.json> <b.json>            byte-level diff of two coding backups
      esys cheat --file <FDLCodes.xml> [--cafd HU_NBT]
                                             list coding options from a cheat sheet
      esys demo                              full workflow against the virtual car (no real car)
      esys version

    SAFETY: writes to a real car require a backup (esys read) and the HU_NBT
    security algorithm, which is not implemented yet — see Docs/PROTOCOL.md.
    """)

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
            print("  read section \(did)")
        }
        print("\(backup.sections.count) sections, \(backup.sections.reduce(0) { $0 + $1.bytes.count }) bytes")
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
                print("    section \(op.group) byte \(op.start)\(op.start == op.end ? "" : "...\(op.end)")" +
                      " mask \(String(op.mask, radix: 2)) = \(op.value)")
            }
        }
        print("\n\(codes.count) options. Apply one with the app once the write path is enabled.")
    } catch {
        fail("\(error)")
    }

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
    let before = car.codingBytes(did: 3000)![96]
    let modified = try await session.applyOperations([MockCar.demoOperation()], to: backup,
                                                      description: "demo bit",
                                                      security: MockCarAlgorithm())
    let after = car.codingBytes(did: 3000)![96]
    print("4. applied demo edit — section 3000 byte 96: \(String(before, radix: 16)) -> " +
          String(after, radix: 16) + " (security unlocked, verified by re-read)")

    // 5. Diff
    print("5. diff old -> new:\n   " + describeDiffs(backup.diff(to: modified))
        .replacingOccurrences(of: "\n", with: "\n   "))

    // 6. Restore
    try await session.restore(backup, security: MockCarAlgorithm())
    let backToOriginal = car.codingBytes(did: 3000)![96] == before
    print("6. restore from backup — byte 96 back to \(String(car.codingBytes(did: 3000)![96], radix: 16)): " +
          (backToOriginal ? "OK" : "FAILED"))
    print("\ndemo complete — the same flow against a real car needs: ENET cable, " +
          "the real HU_NBT security algorithm (Docs/PROTOCOL.md), and a verified cheat entry.")

default:
    fail("unknown command '\(command)' — try `esys help`")
}
