import Foundation

/// UDS (ISO 14229) service layer carried inside HSFZ / DoIP frames.
public enum UDS {
    // Service identifiers used by BMW F-series coding.
    public static let diagnosticSessionControl: UInt8 = 0x10
    public static let ecuReset: UInt8 = 0x11
    public static let clearDTC: UInt8 = 0x14
    public static let readDTC: UInt8 = 0x19
    public static let readDataByID: UInt8 = 0x22
    public static let writeDataByID: UInt8 = 0x2E
    public static let communicationControl: UInt8 = 0x28
    public static let routineControl: UInt8 = 0x31
    public static let securityAccess: UInt8 = 0x27
    public static let testerPresent: UInt8 = 0x3E
    public static let controlDTCSetting: UInt8 = 0x85

    // Sessions
    public static let defaultSession: UInt8 = 0x01
    public static let extendedSession: UInt8 = 0x03
    public static let programmingSession: UInt8 = 0x02

    // MARK: Request builders

    public static func session(_ session: UInt8) -> [UInt8] { [diagnosticSessionControl, session] }

    public static func testerPresent(suppressResponse: Bool = true) -> [UInt8] {
        [testerPresent, suppressResponse ? 0x80 : 0x00]
    }

    public static func readDID(_ did: UInt16) -> [UInt8] {
        [readDataByID] + Bytes.u16be(did)
    }

    /// Read several DIDs in one request (BMW modules support this).
    public static func readDIDs(_ dids: [UInt16]) -> [UInt8] {
        [readDataByID] + dids.flatMap { Bytes.u16be($0) }
    }

    public static func writeDID(_ did: UInt16, _ data: [UInt8]) -> [UInt8] {
        [writeDataByID] + Bytes.u16be(did) + data
    }

    public static func securitySeedRequest(level: UInt8) -> [UInt8] {
        [securityAccess, level]
    }

    public static func securityKey(level: UInt8, key: [UInt8]) -> [UInt8] {
        [securityAccess, level] + key
    }

    public static func ecuReset(_ type: UInt8 = 0x01) -> [UInt8] { [ecuReset, type] }

    public static func startRoutine(_ id: UInt16, data: [UInt8] = []) -> [UInt8] {
        [routineControl, 0x01] + Bytes.u16be(id) + data
    }

    public static func requestRoutineResults(_ id: UInt16) -> [UInt8] {
        [routineControl, 0x03] + Bytes.u16be(id)
    }
}

/// Negative response codes (subset relevant to coding).
public enum UDSNRC: UInt8, CustomStringConvertible, Sendable {
    case generalReject = 0x10
    case serviceNotSupported = 0x11
    case subFunctionNotSupported = 0x12
    case incorrectMessageLength = 0x13
    case responseTooLong = 0x14
    case busyRepeatRequest = 0x21
    case conditionsNotCorrect = 0x22
    case requestSequenceError = 0x24
    case requestOutOfRange = 0x31
    case securityAccessDenied = 0x33
    case invalidKey = 0x35
    case exceedNumberOfAttempts = 0x36
    case requiredTimeDelayNotExpired = 0x37
    case generalProgrammingFailure = 0x72
    case responsePending = 0x78
    case subFunctionNotSupportedInActiveSession = 0x7E
    case serviceNotSupportedInActiveSession = 0x7F

    public var description: String {
        switch self {
        case .generalReject: return "generalReject"
        case .serviceNotSupported: return "serviceNotSupported"
        case .subFunctionNotSupported: return "subFunctionNotSupported"
        case .incorrectMessageLength: return "incorrectMessageLengthOrInvalidFormat"
        case .responseTooLong: return "responseTooLong"
        case .busyRepeatRequest: return "busyRepeatRequest"
        case .conditionsNotCorrect: return "conditionsNotCorrect"
        case .requestSequenceError: return "requestSequenceError"
        case .requestOutOfRange: return "requestOutOfRange"
        case .securityAccessDenied: return "securityAccessDenied"
        case .invalidKey: return "invalidKey"
        case .exceedNumberOfAttempts: return "exceedNumberOfAttempts"
        case .requiredTimeDelayNotExpired: return "requiredTimeDelayNotExpired"
        case .generalProgrammingFailure: return "generalProgrammingFailure"
        case .responsePending: return "responsePending"
        case .subFunctionNotSupportedInActiveSession: return "subFunctionNotSupportedInActiveSession"
        case .serviceNotSupportedInActiveSession: return "serviceNotSupportedInActiveSession"
        }
    }
}
