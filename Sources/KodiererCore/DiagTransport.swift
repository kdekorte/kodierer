import Foundation

/// Anything that can carry a UDS request to an ECU and bring back its reply.
/// Implemented by the HSFZ connection (F-series, TCP 6801), the DoIP client
/// (G-series, TCP 13400) and the loopback link used against the virtual car.
public protocol DiagTransport: AnyObject {
    /// The tester address we present on the wire.
    var testerAddress: UInt8 { get }
    var isOpen: Bool { get }
    /// Send `uds` to `ecu` and wait for the matching reply payload.
    func request(to ecu: UInt8, _ uds: [UInt8], timeout: TimeInterval) async throws -> [UInt8]
    func close()
}

public enum TransportError: Error, CustomStringConvertible, Sendable {
    case notConnected
    case alreadyUsed
    case connectTimeout(String)
    case dropped(String)

    public var description: String {
        switch self {
        case .notConnected: return "not connected"
        case .alreadyUsed: return "connection already used, create a new one"
        case .connectTimeout(let target): return "connect timeout (\(target))"
        case .dropped(let why): return "connection dropped: \(why)"
        }
    }
}
