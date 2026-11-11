import Foundation

/// A car that answered the UDP vehicle search (or a TCP identification).
public struct VehicleAdvertisement: Equatable, Sendable {
    public let host: String
    public let gatewayAddress: UInt8?
    public let mac: String?
    public let vin: String?
    public let raw: [UInt8]

    /// Parses the gateway identification payload:
    /// `DIAGADR10BMWMAC001A37DEC550BMWVIN<WBA8E9G51GNT12345>`
    public static func parse(host: String, payload: [UInt8]) -> VehicleAdvertisement {
        let text = Bytes.ascii(payload)
        var gateway: UInt8?
        var mac: String?
        var vin: String?
        if let adrRange = text.range(of: "DIAGADR") {
            let rest = text[adrRange.upperBound...]
            if rest.count >= 2, let value = UInt8(rest.prefix(2), radix: 16) {
                gateway = value
            }
        }
        if let macRange = text.range(of: "BMWMAC") {
            let rest = String(text[macRange.upperBound...])
            if rest.count >= 12 {
                mac = String(rest.prefix(12))
            }
        }
        if let vinRange = text.range(of: "BMWVIN") {
            vin = String(text[vinRange.upperBound...].prefix(17))
        }
        return VehicleAdvertisement(host: host, gatewayAddress: gateway, mac: mac, vin: vin, raw: payload)
    }
}
