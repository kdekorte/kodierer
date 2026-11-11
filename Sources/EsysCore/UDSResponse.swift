import Foundation

/// A parsed UDS reply.
public struct UDSResponse: Equatable, Sendable {
    public let raw: [UInt8]

    public init(raw: [UInt8]) { self.raw = raw }

    public var isEmpty: Bool { raw.isEmpty }
    public var isNegative: Bool { raw.first == 0x7F }

    /// SID of the request this answers.
    public var requestSID: UInt8? {
        if isNegative { return raw.count >= 2 ? raw[1] : nil }
        return raw.first.map { $0 &- 0x40 }
    }

    public var nrc: UInt8? {
        isNegative && raw.count >= 3 ? raw[2] : nil
    }

    public var isPending: Bool { isNegative && nrc == UDSNRC.responsePending.rawValue }

    /// Payload after the response SID (or after the NRC block for negatives).
    public var data: [UInt8] {
        if isNegative { return raw.count > 3 ? Array(raw.dropFirst(3)) : [] }
        return raw.isEmpty ? [] : Array(raw.dropFirst())
    }

    public var errorDescription: String? {
        guard isNegative, let nrc = nrc else { return nil }
        return UDSNRC(rawValue: nrc).map { "\($0) (0x\(String(nrc, radix: 16)))" }
            ?? "NRC 0x\(String(nrc, radix: 16))"
    }
}

public enum UDSError: Error, CustomStringConvertible, Sendable {
    case negativeResponse(requestSID: UInt8, nrc: UInt8)
    case timeout(ecu: UInt8)
    case noAnswer(ecu: UInt8)
    case unexpectedResponse(String)

    public var description: String {
        switch self {
        case .negativeResponse(let sid, let nrc):
            let name = UDSNRC(rawValue: nrc).map(String.init(describing:)) ?? "unknown"
            return "ECU rejected service 0x\(String(sid, radix: 16)) with \(name) (0x\(String(nrc, radix: 16)))"
        case .timeout(let ecu):
            return "timeout waiting for ECU 0x\(String(ecu, radix: 16))"
        case .noAnswer(let ecu):
            return "no answer from ECU 0x\(String(ecu, radix: 16))"
        case .unexpectedResponse(let what):
            return "unexpected response: \(what)"
        }
    }
}

/// How many bytes after the SID a positive response echoes back (the DID /
/// routine id / sub-function). Used to match replies to requests because the
/// gateway multiplexes several ECUs over one socket.
public func udsEchoByteCount(forRequestSID sid: UInt8) -> Int {
    switch sid {
    case UDS.readDataByID, UDS.writeDataByID, 0x2F: return 2
    case UDS.routineControl: return 3
    case UDS.diagnosticSessionControl, UDS.ecuReset, UDS.readDTC,
         UDS.securityAccess, UDS.communicationControl, UDS.testerPresent,
         UDS.controlDTCSetting: return 1
    default: return 0
    }
}

/// Is `response` the answer to `request`? Compares SID and echoed identifier
/// bytes, not only the SID, so late replies to earlier requests cannot be
/// mistaken for fresh answers.
public func udsAnswers(request: [UInt8], response: [UInt8]) -> Bool {
    guard let reqSID = request.first, !response.isEmpty else { return false }
    if response[0] == 0x7F {
        return response.count >= 3 && response[1] == reqSID
    }
    guard response[0] == reqSID + 0x40 else { return false }
    let echo = udsEchoByteCount(forRequestSID: reqSID)
    guard request.count > echo, response.count > echo else { return false }
    for i in 1...echo {
        // The sub-function byte comes back without the suppress-response bit.
        let sent = (i == 1 && echo != 2) ? request[i] & 0x7F : request[i]
        if response[i] != sent { return false }
    }
    return true
}
