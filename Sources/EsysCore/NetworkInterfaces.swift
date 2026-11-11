import Foundation

/// One network interface of this machine, as reported by getifaddrs.
public struct InterfaceInfo: Equatable, Sendable {
    public let name: String
    public let ipv4: [String]

    /// True when this interface has a link-local address (169.254.x.x) — the
    /// sign that the ENET link to the car is up and configured.
    public var hasLinkLocal: Bool { ipv4.contains { $0.hasPrefix("169.254.") } }
}

/// Lists this machine's IPv4 interfaces — used to check the ENET link and to
/// sweep our own subnets for the car when broadcast discovery finds nothing.
public enum NetworkInterfaces {
    /// All interfaces with IPv4 addresses (loopback included).
    public static func list() -> [InterfaceInfo] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var byName: [String: [String]] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard let sockaddrPtr = interface.ifa_addr else { continue }
            guard sockaddrPtr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var address = UnsafeRawPointer(sockaddrPtr).load(as: sockaddr_in.self)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address.sin_addr, &buffer,
                            socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let name = String(cString: interface.ifa_name)
            byName[name, default: []].append(String(cString: buffer))
        }
        return byName.map { InterfaceInfo(name: $0.key, ipv4: $0.value) }
            .sorted { $0.name < $1.name }
    }

    /// Link-local IPv4 addresses of this machine (169.254.x.x).
    public static func linkLocalAddresses() -> [String] {
        list().flatMap(\.ipv4).filter { $0.hasPrefix("169.254.") }
    }

    /// The /24 prefixes of our link-local addresses, e.g. "169.254.9".
    public static func linkLocalSubnets() -> [String] {
        var subnets: Set<String> = []
        for address in linkLocalAddresses() {
            let parts = address.split(separator: ".")
            guard parts.count == 4 else { continue }
            subnets.insert("\(parts[0]).\(parts[1]).\(parts[2])")
        }
        return subnets.sorted()
    }
}
