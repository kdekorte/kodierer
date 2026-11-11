import Foundation

/// What we know about one ECU after scanning the vehicle.
public struct ECUInfo: Equatable, Sendable {
    public let address: UInt8
    public let name: String?
    public let vin: String?
    public let svk: SVK?
    /// Raw identification reads, DID -> bytes.
    public let ids: [UInt16: [UInt8]]

    public var displayName: String {
        let hex = String(format: "0x%02X", address)
        return name.map { "\($0) [\(hex)]" } ?? "[\(hex)]"
    }
}

/// Identity of the whole vehicle, read from the gateway (VCM).
public struct VehicleIdentity: Equatable, Sendable {
    public let vin: String?
    /// Raw FA (vehicle order) bytes from DID 0x3F06.
    public let fa: [UInt8]?
    /// Raw I-Step bytes from DID 0x100B (e.g. F020-17-07-503).
    public let iStep: [UInt8]?

    /// I-Steps decoded as text: current, last, shipment.
    public var iStepText: [String] {
        guard let iStep, iStep.count >= 24 else { return [] }
        var steps: [String] = []
        for index in stride(from: 0, to: min(24, iStep.count), by: 8) {
            let block = Array(iStep[index..<min(index + 8, iStep.count)])
            guard block.count == 8 else { continue }
            let series = Bytes.ascii(Array(block[0..<4]))
            let year = String(format: "%02d", block[4])
            let month = String(format: "%02d", block[5])
            let counter = (Int(block[6]) << 8) | Int(block[7])
            steps.append("\(series)-\(year)-\(month)-\(String(format: "%03d", counter))")
        }
        return steps
    }
}

/// Reads identity data and scans the SVT (the list of installed ECUs).
///
/// E-Sys reads the SVT from the gateway; a robust client can build the same
/// picture by asking every address in turn: an ECU that is present answers
/// TesterPresent, and then reports its name (DID 0xF197), VIN (0xF190) and
/// software version container (0xF101).
public enum SVTScan {
    /// Reads VIN / FA / I-Step from the gateway (ZGW, 0x10).
    public static func readVehicleIdentity(_ transport: DiagTransport,
                                           timeout: TimeInterval = 2) async -> VehicleIdentity {
        func read(_ did: UInt16) async -> [UInt8]? {
            guard let reply = try? await transport.request(
                to: BMWAddresses.gateway, UDS.readDID(did), timeout: timeout) else { return nil }
            let response = UDSResponse(raw: reply)
            guard !response.isNegative, response.data.count > 2 else { return nil }
            // Response: [62][DID hi][DID lo][data...]
            return Array(response.data.dropFirst(2))
        }
        let vin = await read(BMWDID.vin).map { String(Bytes.ascii($0).suffix(17)) }
        let fa = await read(BMWDID.fa)
        let iStep = await read(BMWDID.iStep)
        return VehicleIdentity(vin: vin, fa: fa, iStep: iStep)
    }

    /// Walks `range` and collects every ECU that answers.
    /// - Parameters:
    ///   - dwell: per-address timeout; 0.25 s keeps a full scan under a minute.
    ///   - progress: called on a background thread for each module found.
    @discardableResult
    public static func scan(_ transport: DiagTransport,
                            range: ClosedRange<UInt8> = 0x10...0xF9,
                            dwell: TimeInterval = 0.25,
                            progress: (@Sendable (ECUInfo) -> Void)? = nil) async -> [ECUInfo] {
        var found: [ECUInfo] = []
        for address in range {
            // Any answer proves something lives here, even a negative one.
            guard (try? await transport.request(
                to: address, UDS.testerPresent(suppressResponse: false), timeout: dwell)) != nil
            else { continue }
            var ids: [UInt16: [UInt8]] = [:]
            for did in [BMWDID.ecuName, BMWDID.vin, BMWDID.svk] {
                guard let reply = try? await transport.request(
                    to: address, UDS.readDID(did), timeout: dwell), !reply.isEmpty
                else { continue }
                let response = UDSResponse(raw: reply)
                if !response.isNegative, response.data.count > 2 {
                    ids[did] = Array(response.data.dropFirst(2))
                }
            }
            let info = ECUInfo(
                address: address,
                name: ids[BMWDID.ecuName].map { Bytes.ascii($0).trimmingCharacters(in: .whitespaces) },
                vin: ids[BMWDID.vin].map { Bytes.ascii($0) },
                svk: ids[BMWDID.svk].map { SVK.parse($0) },
                ids: ids)
            found.append(info)
            progress?(info)
        }
        return found
    }

    /// Finds a module by name (e.g. "HU_NBT") in a scan result.
    public static func find(named name: String, in modules: [ECUInfo]) -> ECUInfo? {
        let wanted = name.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return modules.first { module in
            guard let module = module.name else { return false }
            return module.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" } == wanted
        }
    }
}
