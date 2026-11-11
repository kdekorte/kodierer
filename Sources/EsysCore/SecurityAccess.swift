import Foundation

/// Computes the UDS SecurityAccess key for a seed. BMW modules hand out an
/// 8-byte seed and expect the matching key computed by an ECU-specific
/// algorithm (E-Sys gets it from the SGBD data in PSdZData).
///
/// The real HU_NBT algorithm still has to be researched before writing to a
/// real car — see Docs/PROTOCOL.md, "Security access". Until then the write
/// path works against the virtual car (which uses `MockCarAlgorithm`).
public protocol SecurityAlgorithm: Sendable {
    var name: String { get }
    /// The key for `seed` at security `level`, or nil when the algorithm does
    /// not cover this level / ECU.
    func key(forSeed seed: [UInt8], level: UInt8, ecu: UInt8) -> [UInt8]?
}

/// The algorithm the virtual car accepts: the seed reversed. Test/demo only.
public struct MockCarAlgorithm: SecurityAlgorithm {
    public let name = "mockcar"
    public init() {}
    public func key(forSeed seed: [UInt8], level: UInt8, ecu: UInt8) -> [UInt8]? {
        guard seed.count == 8 else { return nil }
        return seed.reversed()
    }
}

public enum SecurityAccessError: Error, CustomStringConvertible, Sendable {
    case noAlgorithm
    case seedLengthUnexpected(Int)
    case rejected(nrc: UInt8)
    case algorithmReturnedNil(String)

    public var description: String {
        switch self {
        case .noAlgorithm:
            return "security access required but no seed/key algorithm is available for this ECU " +
                "(see Docs/PROTOCOL.md — the HU_NBT algorithm is still to be researched)"
        case .seedLengthUnexpected(let length):
            return "unexpected seed length \(length) (BMW modules use 8 bytes)"
        case .rejected(let nrc):
            let reason = UDSNRC(rawValue: nrc).map(String.init(describing:)) ?? "NRC \(nrc)"
            return "security access rejected: \(reason)"
        case .algorithmReturnedNil(let name):
            return "security algorithm \"\(name)\" cannot handle this seed/level"
        }
    }
}

/// UDS SecurityAccess (service 0x27): request a seed at an odd level, send the
/// key at the following even level.
public enum SecurityAccess {
    /// Unlocks `ecu` for coding writes. `level` must be odd (0x11 is the usual
    /// coding level; some modules want 0x01).
    public static func unlock(_ transport: DiagTransport,
                              ecu: UInt8,
                              level: UInt8 = 0x11,
                              algorithm: SecurityAlgorithm?,
                              timeout: TimeInterval = 2) async throws {
        guard let algorithm else { throw SecurityAccessError.noAlgorithm }
        guard level & 1 == 1 else {
            throw SecurityAccessError.rejected(nrc: UDSNRC.subFunctionNotSupported.rawValue)
        }
        // 1. Seed request.
        let seedReply = UDSResponse(raw: try await transport.request(
            to: ecu, UDS.securitySeedRequest(level: level), timeout: timeout))
        if seedReply.isNegative, let nrc = seedReply.nrc {
            throw SecurityAccessError.rejected(nrc: nrc)
        }
        guard seedReply.raw.first == 0x67, seedReply.raw.count >= 3 else {
            throw UDSError.unexpectedResponse("expected positive security access answer")
        }
        // An already-unlocked module returns an all-zero seed; sending the
        // computed key anyway is harmless (all-zero key is accepted).
        let seed = Array(seedReply.raw.dropFirst(2))
        guard seed.count == 8 else { throw SecurityAccessError.seedLengthUnexpected(seed.count) }
        // 2. Compute and send the key.
        guard let key = algorithm.key(forSeed: seed, level: level, ecu: ecu) else {
            throw SecurityAccessError.algorithmReturnedNil(algorithm.name)
        }
        let keyReply = UDSResponse(raw: try await transport.request(
            to: ecu, UDS.securityKey(level: level + 1, key: key), timeout: timeout))
        if keyReply.isNegative, let nrc = keyReply.nrc {
            throw SecurityAccessError.rejected(nrc: nrc)
        }
        guard keyReply.raw.first == 0x67 else {
            throw UDSError.unexpectedResponse("expected positive key acceptance")
        }
    }
}
