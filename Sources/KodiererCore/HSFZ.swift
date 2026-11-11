import Foundation

/// BMW HSFZ — the framing F-series gateways (ZGW) speak on TCP 6801.
///
/// Wire format:
///
///     [UInt32 BE length][UInt16 BE control][body...]
///
/// `length` counts every byte after the 6-byte header. For diagnostic frames
/// the body is `[src][dst][UDS request/response...]`, so length = 2 + UDS byte count.
///
/// Sources: MIT-licensed reverse engineering (kaiwen-z/bmw-enet-tool, egzey0/svietlik)
/// cross-checked against kdrcoding/fake-car, an E-Sys-compatible car simulator.
/// See Docs/PROTOCOL.md for details and links.
public enum HSFZControl: UInt16, CaseIterable, Sendable {
    /// Real application data (UDS payload) between tester and ECU.
    case diag = 0x0001
    /// Gateway echo / acknowledgement of a request. Clients must ignore these.
    case ack = 0x0002
    /// Vehicle identification request/response (UDP 6811, also answered on TCP).
    case ident = 0x0011
    /// Keep-alive.
    case alive = 0x0012
}

/// HSFZ-level error control words a gateway can send instead of answering.
public enum HSFZProtocolError: Error, CustomStringConvertible, Equatable, Sendable {
    case incorrectTesterAddress        // 0x40
    case incorrectControlWord          // 0x41
    case incorrectFormat               // 0x42
    case incorrectDestinationAddress   // 0x43
    case messageTooLarge               // 0x44
    case diagnosticApplicationNotReady // 0x45
    case outOfMemory                   // 0xFF

    public var description: String {
        switch self {
        case .incorrectTesterAddress: return "HSFZ: incorrect tester address (0x40)"
        case .incorrectControlWord: return "HSFZ: incorrect control word (0x41)"
        case .incorrectFormat: return "HSFZ: incorrect format (0x42)"
        case .incorrectDestinationAddress: return "HSFZ: incorrect destination address (0x43)"
        case .messageTooLarge: return "HSFZ: message too large (0x44)"
        case .diagnosticApplicationNotReady: return "HSFZ: diagnostic application not ready (0x45)"
        case .outOfMemory: return "HSFZ: gateway out of memory (0xFF)"
        }
    }

    /// Maps an unexpected control word to an error. Returns nil when the word is not a known error.
    public static func from(controlWord: UInt16) -> HSFZProtocolError? {
        switch controlWord {
        case 0x40: return .incorrectTesterAddress
        case 0x41: return .incorrectControlWord
        case 0x42: return .incorrectFormat
        case 0x43: return .incorrectDestinationAddress
        case 0x44: return .messageTooLarge
        case 0x45: return .diagnosticApplicationNotReady
        case 0xFF: return .outOfMemory
        default: return nil
        }
    }
}

/// One HSFZ frame.
public struct HSFZFrame: Equatable, Sendable {
    public var control: UInt16
    /// Everything after the 6-byte header. For diag frames: `[src, dst, uds...]`.
    public var body: [UInt8]

    public init(control: UInt16, body: [UInt8]) {
        self.control = control
        self.body = body
    }

    /// Diagnostic frame from `src` to `dst` carrying a UDS payload.
    public static func diag(src: UInt8, dst: UInt8, uds: [UInt8]) -> HSFZFrame {
        HSFZFrame(control: HSFZControl.diag.rawValue, body: [src, dst] + uds)
    }

    /// Vehicle identification request (empty body, control 0x0011). Also used on UDP 6811.
    public static func identRequest() -> HSFZFrame {
        HSFZFrame(control: HSFZControl.ident.rawValue, body: [])
    }

    /// Keep-alive request.
    public static func aliveRequest() -> HSFZFrame {
        HSFZFrame(control: HSFZControl.alive.rawValue, body: [])
    }

    public static let headerLength = 6
    public static let maxBodyLength = 1 << 20

    public var isDiag: Bool { control == HSFZControl.diag.rawValue }
    public var isAck: Bool { control == HSFZControl.ack.rawValue }
    public var isAlive: Bool { control == HSFZControl.alive.rawValue }
    public var isIdent: Bool { control == HSFZControl.ident.rawValue }

    /// Source address of a diagnostic frame (the ECU that answered, or our tester address).
    public var src: UInt8? { isDiag && body.count >= 1 ? body[0] : nil }
    /// Destination address of a diagnostic frame.
    public var dst: UInt8? { isDiag && body.count >= 2 ? body[1] : nil }
    /// The UDS payload of a diagnostic frame.
    public var uds: [UInt8]? { isDiag && body.count >= 2 ? Array(body.dropFirst(2)) : nil }

    public func encoded() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(HSFZFrame.headerLength + body.count)
        out.append(contentsOf: Bytes.u32be(UInt32(body.count)))
        out.append(contentsOf: Bytes.u16be(control))
        out.append(contentsOf: body)
        return out
    }

    /// Total wire size (header + body) of the frame whose 6-byte header is `header`.
    /// Returns nil when the header is too short, throws when the length is implausible.
    public static func totalWireLength(ofHeader header: [UInt8]) throws -> Int? {
        guard header.count >= headerLength else { return nil }
        guard let length = Bytes.readU32BE(header, at: 0) else { return nil }
        guard length <= maxBodyLength else { throw HSFZProtocolError.messageTooLarge }
        return headerLength + Int(length)
    }

    /// Parses one frame off the front of `buffer`.
    /// - Returns: nil when the buffer does not hold a complete frame yet.
    /// - Throws: `HSFZProtocolError` when the length field is implausible.
    public static func parse(_ buffer: [UInt8]) throws -> HSFZFrame? {
        guard let total = try totalWireLength(ofHeader: buffer) else { return nil }
        guard buffer.count >= total else { return nil }
        let control = Bytes.readU16BE(buffer, at: 4) ?? 0
        return HSFZFrame(control: control, body: Array(buffer[headerLength..<total]))
    }
}
