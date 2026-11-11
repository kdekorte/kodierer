import Foundation

/// High-level workflow over one connection: identify the car, scan the SVT,
/// read coding data, apply changes, restore.
public final class VehicleSession {
    public let transport: DiagTransport
    public private(set) var identity: VehicleIdentity?

    public init(transport: DiagTransport) {
        self.transport = transport
    }

    /// Reads VIN / FA / I-Step from the gateway.
    @discardableResult
    public func readIdentity(timeout: TimeInterval = 2) async -> VehicleIdentity {
        let identity = await SVTScan.readVehicleIdentity(transport, timeout: timeout)
        self.identity = identity
        return identity
    }

    /// Walks the address space and lists every ECU that answers.
    @discardableResult
    public func scanSVT(range: ClosedRange<UInt8> = 0x10...0xF9,
                        dwell: TimeInterval = 0.25,
                        progress: (@Sendable (ECUInfo) -> Void)? = nil) async -> [ECUInfo] {
        await SVTScan.scan(transport, range: range, dwell: dwell, progress: progress)
    }

    /// Reads the full coding data of an ECU into a backup snapshot.
    public func readCoding(ecu: UInt8,
                           ecuName: String? = nil,
                           dids: [Int]? = nil,
                           timeout: TimeInterval = 2,
                           progress: (@Sendable (Int) -> Void)? = nil) async throws -> CodingBackup {
        var vin = identity?.vin
        if vin == nil {
            let identity = await readIdentity(timeout: timeout)
            vin = identity.vin
        }
        return try await CodingEngine.readCoding(transport, ecu: ecu, ecuName: ecuName,
                                                 vin: vin, dids: dids, timeout: timeout,
                                                 progress: progress)
    }

    /// Applies a named cheat-sheet code to a backup and writes back only the
    /// changed sections. Re-reads and verifies afterwards.
    /// - Returns: the new snapshot (equal to the old one when nothing changed).
    @discardableResult
    public func apply(_ code: FDLCheatCode,
                      to backup: CodingBackup,
                      security: SecurityAlgorithm? = nil,
                      verify: Bool = true) async throws -> CodingBackup {
        try await applyOperations(code.operations, to: backup,
                                  description: code.description, security: security, verify: verify)
    }

    /// Applies raw byte operations to a backup and writes back only the
    /// changed sections.
    @discardableResult
    public func applyOperations(_ operations: [FDLOperation],
                                to backup: CodingBackup,
                                description: String? = nil,
                                security: SecurityAlgorithm? = nil,
                                verify: Bool = true) async throws -> CodingBackup {
        let ecu = UInt8(backup.ecuAddress)
        var modified = backup
        for operation in operations {
            guard var section = modified.section(operation.group) else {
                throw FDLEditError.sectionMissing(operation.group)
            }
            section.setBytes(try operation.applied(to: section.bytes))
            modified.replace(section: section)
        }
        let diffs = backup.diff(to: modified)
        guard !diffs.isEmpty else {
            // Already in the wanted state — nothing to write.
            return backup
        }
        let changedDIDs = diffs.filter { !$0.isEmpty }.map(\.did)
        let changedSections = modified.sections.filter { changedDIDs.contains($0.did) }
        try await CodingEngine.writeSections(transport, ecu: ecu, sections: changedSections,
                                             security: security)
        if verify {
            let reread = try await CodingEngine.readCoding(transport, ecu: ecu,
                                                            ecuName: backup.ecuName,
                                                            vin: backup.vin, dids: changedDIDs)
            for did in changedDIDs {
                guard reread.sectionBytes(did) == modified.sectionBytes(did) else {
                    throw UDSError.unexpectedResponse(
                        "verification failed: section \(did) reads back different after writing")
                }
            }
        }
        return modified
    }

    /// Writes a whole backup back to the ECU (recovery path).
    public func restore(_ backup: CodingBackup, security: SecurityAlgorithm? = nil) async throws {
        try await CodingEngine.restore(transport, backup: backup, security: security)
    }
}
