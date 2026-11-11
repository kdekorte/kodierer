import Foundation

/// Finds F-series cars on the link-local network.
///
/// F-series gateways do **not** answer DoIP vehicle identification; they answer
/// an HSFZ identification request (empty body, control word 0x0011) sent to
/// UDP port 6811 — usually as a broadcast. The reply comes back from the
/// gateway's own address and identifies it (`DIAGADR..BMWMAC..BMWVIN..`).
public enum HSFZDiscovery {
    public static let identPort: UInt16 = 6811
    public static let diagPort: UInt16 = HSFZConnection.defaultPort

    /// The identification request in wire form: `00 00 00 00 00 11`.
    public static func identRequest() -> [UInt8] { HSFZFrame.identRequest().encoded() }

    /// Broadcast addresses tried when searching: the link-local directed
    /// broadcast plus the global broadcast.
    public static var broadcastAddresses: [String] {
        ["255.255.255.255", "169.254.255.255"]
    }

    /// Candidate gateway addresses to probe directly (TCP 6801) when no car
    /// answers the broadcast. ZGWs observed in the wild: 169.254.0.2,
    /// 169.254.9.100 ... 169.254.9.105.
    public static var candidateHosts: [String] {
        var hosts = ["169.254.0.2", "169.254.9.1", "169.254.9.100", "169.254.9.103",
                     "169.254.9.104", "169.254.9.105"]
        hosts += (100...110).map { "169.254.0.\($0)" }
        return hosts
    }

    /// Broadcasts the identification request and collects answers until `timeout`.
    /// - Parameter unicast: extra hosts to ask directly (tests, or blocked broadcasts).
    @discardableResult
    public static func findCars(timeout: TimeInterval = 2.0,
                                unicast: [String] = []) async -> [VehicleAdvertisement] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: findCarsBlocking(timeout: timeout, unicast: unicast))
            }
        }
    }

    static func findCarsBlocking(timeout: TimeInterval, unicast: [String]) -> [VehicleAdvertisement] {
        var results: [String: VehicleAdvertisement] = [:]
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var rcvTimeout = timeval(tv_sec: 0, tv_usec: 150_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcvTimeout, socklen_t(MemoryLayout<timeval>.size))

        let request = identRequest()
        var targets = broadcastAddresses + unicast
        // Also ask every host in our own link-local /24 subnets directly —
        // covers the case where the Mac and the car ended up in the same
        // subnet but broadcast is filtered somewhere on the way.
        for subnet in NetworkInterfaces.linkLocalSubnets() {
            targets += (1...254).map { "\(subnet).\($0)" }
        }
        for target in targets {
            guard let addr = sockaddr_in(address: target, port: identPort) else { continue }
            withUnsafePointer(to: addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    request.withUnsafeBytes { raw in
                        _ = sendto(fd, raw.baseAddress, request.count, 0, sockaddrPointer,
                                   socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 1024)
        while Date() < deadline {
            var fromAddr = sockaddr()
            var fromLen = socklen_t(MemoryLayout<sockaddr>.size)
            let received = withUnsafeMutablePointer(to: &fromAddr) { pointer -> Int in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &fromLen)
                }
            }
            guard received > 0 else { continue }
            let payload = Array(buffer[0..<received])
            guard payload.count > HSFZFrame.headerLength,
                  Bytes.readU16BE(payload, at: 4) == HSFZControl.ident.rawValue else { continue }
            let body = Array(payload.dropFirst(HSFZFrame.headerLength))
            guard let host = fromAddr.ipAddressString() else { continue }
            if results[host] == nil {
                results[host] = VehicleAdvertisement.parse(host: host, payload: body)
            }
        }
        return Array(results.values)
    }

    /// Probes likely gateway addresses for an open diagnostic port.
    public static func probeCandidates(timeout: TimeInterval = 0.4) async -> [String] {
        var found: [String] = []
        await withTaskGroup(of: (String, Bool).self) { group in
            for host in candidateHosts {
                group.addTask {
                    (host, await HSFZConnection.probe(host: host, timeout: timeout))
                }
            }
            for await (host, reachable) in group where reachable {
                found.append(host)
            }
        }
        return found
    }
}

extension sockaddr {
    /// The sender's IPv4 address as a dotted string, if this is an IPv4 sockaddr.
    func ipAddressString() -> String? {
        guard self.sa_family == UInt8(AF_INET) else { return nil }
        return withUnsafeBytes(of: self) { raw in
            guard let base = raw.bindMemory(to: sockaddr_in.self).first else { return nil }
            var addr = base.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buffer)
        }
    }
}

extension sockaddr_in {
    init?(address: String, port: UInt16) {
        var addr = in_addr()
        guard inet_pton(AF_INET, address, &addr) == 1 else { return nil }
        self.init(sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                  sin_family: sa_family_t(AF_INET),
                  sin_port: port.bigEndian,
                  sin_addr: addr,
                  sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    }
}

