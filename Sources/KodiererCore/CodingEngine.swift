import Foundation

/// Reads and writes FDL coding data over a diagnostic transport.
///
/// Read = ReadDataByIdentifier (0x22) per section DID.
/// Write = extended session (10 03) → SecurityAccess (27) → WriteDataByIdentifier
/// (2E) per changed section. This mirrors what E-Sys does for FDL coding.
public enum CodingEngine {
    /// Probes a DID range for sections the ECU actually has.
    /// Unknown DIDs are answered with requestOutOfRange, which is harmless.
    public static func discoverSections(_ transport: DiagTransport,
                                        ecu: UInt8,
                                        range: ClosedRange<Int> = BMWDID.codingSectionRange,
                                        timeout: TimeInterval = 1,
                                        progress: (@Sendable (Int) -> Void)? = nil) async -> [Int] {
        var found: [Int] = []
        for did in range {
            guard let reply = try? await transport.request(
                to: ecu, UDS.readDID(UInt16(did)), timeout: timeout) else { continue }
            let response = UDSResponse(raw: reply)
            if !response.isNegative, response.data.count > 2 {
                found.append(did)
                progress?(did)
            }
        }
        return found
    }

    /// Reads the whole coding data of an ECU into a backup.
    /// - Parameter dids: sections to read; discovered automatically when nil.
    public static func readCoding(_ transport: DiagTransport,
                                  ecu: UInt8,
                                  ecuName: String? = nil,
                                  vin: String? = nil,
                                  dids: [Int]? = nil,
                                  timeout: TimeInterval = 2,
                                  progress: (@Sendable (Int) -> Void)? = nil) async throws -> CodingBackup {
        let sections: [Int]
        if let dids {
            sections = dids
        } else {
            sections = await discoverSections(transport, ecu: ecu, progress: progress)
        }
        guard !sections.isEmpty else {
            throw UDSError.unexpectedResponse(
                "no coding sections found at ECU 0x\(String(ecu, radix: 16)) " +
                "(is it present, and is the address right?)")
        }
        // Best effort: the SVK names the CAFD this coding data belongs to.
        var svkHex: String?
        if let reply = try? await transport.request(to: ecu, UDS.readDID(BMWDID.svk),
                                                     timeout: timeout) {
            let response = UDSResponse(raw: reply)
            if !response.isNegative, response.data.count > 2 {
                svkHex = Bytes.hexCompact(Array(response.data.dropFirst(2)))
            }
        }
        var backup = CodingBackup(vin: vin, ecuAddress: Int(ecu), ecuName: ecuName,
                                  svkHex: svkHex, sections: [])
        for did in sections {
            let reply = try await transport.request(to: ecu, UDS.readDID(UInt16(did)), timeout: timeout)
            let response = UDSResponse(raw: reply)
            guard !response.isNegative, response.data.count > 2 else {
                throw UDSError.negativeResponse(requestSID: UDS.readDataByID,
                                                nrc: response.nrc ?? UDSNRC.generalReject.rawValue)
            }
            // Response: [62][DID hi][DID lo][data...]
            backup.replace(section: CodingSection(did: did, bytes: Array(response.data.dropFirst(2))))
            progress?(did)
        }
        return backup
    }

    /// Writes sections to an ECU, changing only what is passed in.
    /// `security` is required by real modules; the virtual car uses
    /// `MockCarAlgorithm`.
    public static func writeSections(_ transport: DiagTransport,
                                     ecu: UInt8,
                                     sections: [CodingSection],
                                     security: SecurityAlgorithm? = nil,
                                     securityLevel: UInt8 = 0x11,
                                     reset: Bool = false,
                                     timeout: TimeInterval = 3) async throws {
        guard !sections.isEmpty else { return }

        // 1. Extended diagnostic session.
        let sessionReply = UDSResponse(raw: try await transport.request(
            to: ecu, UDS.session(UDS.extendedSession), timeout: timeout))
        if sessionReply.isNegative, let nrc = sessionReply.nrc {
            throw UDSError.negativeResponse(requestSID: UDS.diagnosticSessionControl, nrc: nrc)
        }

        // 2. Security access.
        try await SecurityAccess.unlock(transport, ecu: ecu, level: securityLevel, algorithm: security)

        // 3. Write each section.
        for section in sections {
            let reply = try await transport.request(
                to: ecu, UDS.writeDID(UInt16(section.did), section.bytes), timeout: timeout)
            let response = UDSResponse(raw: reply)
            if response.isNegative, let nrc = response.nrc {
                if nrc == UDSNRC.securityAccessDenied.rawValue {
                    throw SecurityAccessError.noAlgorithm
                }
                throw UDSError.negativeResponse(requestSID: UDS.writeDataByID, nrc: nrc)
            }
            guard response.raw.first == 0x6E else {
                throw UDSError.unexpectedResponse("expected write confirmation for section \(section.did)")
            }
        }

        // 4. Optional ECU reset so the change takes effect (NBT reboots by
        //    itself after coding; the reset is best-effort).
        if reset {
            _ = try? await transport.request(to: ecu, UDS.ecuReset(0x01), timeout: timeout)
        }
    }

    /// Writes every section of a backup back — the restore path.
    public static func restore(_ transport: DiagTransport,
                               backup: CodingBackup,
                               security: SecurityAlgorithm? = nil,
                               securityLevel: UInt8 = 0x11) async throws {
        try await writeSections(transport, ecu: UInt8(backup.ecuAddress),
                                sections: backup.sections,
                                security: security, securityLevel: securityLevel)
    }
}
