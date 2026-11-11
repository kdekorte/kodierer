import Foundation
import Network

/// An in-process virtual BMW speaking the F-series protocol on loopback:
/// HSFZ framing, gateway acks, one module per diagnostic address, UDS coding
/// reads/writes with security access.
///
/// Everything in it is synthetic demo data — no bytes from any real CAFD or
/// PSdZData. It exists so the whole client stack (connect → SVT scan → coding
/// read → security unlock → write → verify → restore) can be exercised
/// without a car.
public final class MockCar: @unchecked Sendable {
    /// A fake VIN (17 chars) so reports look real.
    public let vin: String
    /// The TCP port the virtual gateway listens on (set by `start()`).
    public private(set) var port: UInt16 = 0

    public struct Module {
        let address: UInt8
        let name: String
        var dids: [UInt16: [UInt8]]
        var session: UInt8 = 1
        var unlocked = false
        let requiresSecurityForWrite: Bool

        init(address: UInt8, name: String, dids: [UInt16: [UInt8]] = [:],
             requiresSecurityForWrite: Bool = false) {
            self.address = address; self.name = name; self.dids = dids
            self.requiresSecurityForWrite = requiresSecurityForWrite
        }
    }

    private let queue = DispatchQueue(label: "esys.mockcar")
    private var listener: NWListener?
    private var modules: [UInt8: Module] = [:]
    private var connections: [ObjectIdentifier: ConnectionBox] = [:]
    private var seeds: [UInt8: [UInt8]] = [:]

    private final class ConnectionBox {
        let connection: NWConnection
        var rx: [UInt8] = []
        init(connection: NWConnection) { self.connection = connection }
    }

    public init(vin: String = "WBA8E9G51GNT00042") {
        self.vin = vin
        buildModules()
    }

    // MARK: Modules (all data synthetic)

    private func buildModules() {
        var gateway = Module(address: BMWAddresses.gateway, name: "ZGW_17")
        gateway.dids[BMWDID.vin] = Array(vin.utf8)
        gateway.dids[BMWDID.ecuName] = Array("ZGW_17".utf8)
        gateway.dids[BMWDID.fa] = Array("F025,6NS,6AC,LCI".utf8)
        gateway.dids[BMWDID.fp] = [0x46, 0x30, 0x32, 0x35, 0x00, 0x01]
        gateway.dids[BMWDID.iStep] = Self.iStepBytes([
            "F025-17-07-503", "F025-17-03-502", "F025-16-11-500"])
        modules[gateway.address] = gateway

        for (address, name) in [(BMWAddresses.dme, "DME"), (BMWAddresses.fem, "FEM"),
                                (BMWAddresses.kombi, "KOMBI")] {
            var module = Module(address: address, name: name)
            module.dids[BMWDID.ecuName] = Array(name.utf8)
            module.dids[BMWDID.vin] = Array(vin.utf8)
            module.dids[BMWDID.svk] = Self.svk(cafdID: UInt32(address) << 16 | 0x0001,
                                               cafdVersions: (12, 0, 1))
            modules[address] = module
        }

        var hu = Module(address: BMWAddresses.huNBT, name: "HU_NBT", requiresSecurityForWrite: true)
        hu.dids[BMWDID.ecuName] = Array("HU_NBT".utf8)
        hu.dids[BMWDID.vin] = Array(vin.utf8)
        hu.dids[BMWDID.svk] = Self.svk(cafdID: 0x0000F007, cafdVersions: (13, 1, 9))
        // Coding sections (block numbers are hex: 0x3000, 0x3001, ...).
        // Byte 96 of section 0x3000 is the demo parameter bit.
        var section3000 = Self.pattern(length: 256)
        section3000[96] = 0x00
        hu.dids[UInt16(0x3000)] = section3000
        hu.dids[UInt16(0x3001)] = Self.pattern(length: 128)
        hu.dids[UInt16(0x3002)] = Self.pattern(length: 64)
        hu.dids[UInt16(0x3010)] = Self.pattern(length: 32)
        modules[hu.address] = hu
    }

    /// The demo edit: set bit 0x10 of byte 96 in section 0x3000 of the head unit.
    public static func demoOperation() -> FDLOperation {
        FDLOperation(group: 0x3000, start: 96, end: 96, mask: 0x10, value: .bytes([0x10]))
    }

    private static func pattern(length: Int) -> [UInt8] {
        (0..<length).map { UInt8(($0 &* 31 &+ 17) & 0xFF) }
    }

    private static func iStepBytes(_ steps: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        for step in steps {
            let parts = step.split(separator: "-").map(String.init)
            guard parts.count == 4 else { continue }
            bytes += Array(parts[0].utf8)
            bytes.append(UInt8(parts[1]) ?? 0)
            bytes.append(UInt8(parts[2]) ?? 0)
            let counter = Int(parts[3]) ?? 0
            bytes.append(UInt8(counter >> 8))
            bytes.append(UInt8(counter & 0xFF))
        }
        return bytes
    }

    private static func svk(cafdID: UInt32, cafdVersions: (UInt8, UInt8, UInt8)) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x02 // entry count (synthetic)
        func entry(_ cls: UInt8, _ id: UInt32, _ v: (UInt8, UInt8, UInt8)) -> [UInt8] {
            [cls, UInt8(id >> 24), UInt8(id >> 16 & 0xFF), UInt8(id >> 8 & 0xFF),
             UInt8(id & 0xFF), v.0, v.1, v.2]
        }
        bytes += entry(0x01, 0x0000A001, (12, 0, 1))                       // main software
        bytes += entry(SVK.cafdProcessClass, cafdID, cafdVersions)          // CAFD
        return bytes
    }

    /// The gateway identification, as a real ZGW answers the vehicle search.
    private var identification: [UInt8] {
        Array("DIAGADR10BMWMAC001A37DEC550BMWVIN\(vin)".utf8)
    }

    // MARK: Lifecycle

    /// Starts listening on 127.0.0.1 (ephemeral TCP port).
    public func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.listener == nil else { cont.resume(); return }
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
                do {
                    let listener = try NWListener(using: params)
                    self.listener = listener
                    var resumed = false
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            self.port = listener.port?.rawValue ?? 0
                            if !resumed { resumed = true; cont.resume() }
                        case .failed(let error):
                            if !resumed { resumed = true; cont.resume(throwing: error) }
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { connection in
                        self.accept(connection)
                    }
                    listener.start(queue: self.queue)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        queue.async {
            self.listener?.stateUpdateHandler = nil
            self.listener?.newConnectionHandler = nil
            self.listener?.cancel()
            self.listener = nil
            for box in self.connections.values { box.connection.cancel() }
            self.connections.removeAll()
        }
    }

    // MARK: Inspection (for tests and the demo)

    public func codingBytes(ecu: UInt8 = BMWAddresses.huNBT, did: Int) -> [UInt8]? {
        queue.sync { modules[ecu]?.dids[UInt16(did)] }
    }

    public func setCodingBytes(ecu: UInt8, did: Int, bytes: [UInt8]) {
        queue.async { self.modules[ecu]?.dids[UInt16(did)] = bytes }
    }

    public func moduleNames() -> [UInt8: String] {
        queue.sync { modules.mapValues(\.name) }
    }

    public var huNBTAddress: UInt8 { BMWAddresses.huNBT }

    // MARK: Networking

    private func accept(_ connection: NWConnection) {
        let box = ConnectionBox(connection: connection)
        connections[ObjectIdentifier(connection)] = box
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.receive(box)
            case .failed, .cancelled:
                self.connections[ObjectIdentifier(connection)] = nil
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(_ box: ConnectionBox) {
        box.connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                box.rx.append(contentsOf: data)
                self.processBuffer(box)
            }
            guard error == nil, !isComplete else {
                self.connections[ObjectIdentifier(box.connection)] = nil
                return
            }
            self.receive(box)
        }
    }

    private func processBuffer(_ box: ConnectionBox) {
        while box.rx.count >= HSFZFrame.headerLength {
            guard let parsed = try? HSFZFrame.parse(box.rx),
                  box.rx.count >= HSFZFrame.headerLength + parsed.body.count else { return }
            box.rx.removeFirst(HSFZFrame.headerLength + parsed.body.count)
            handle(parsed, box)
        }
    }

    private func send(_ box: ConnectionBox, _ bytes: [UInt8]) {
        box.connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }

    // MARK: Frame handling

    private func handle(_ frame: HSFZFrame, _ box: ConnectionBox) {
        switch frame.control {
        case HSFZControl.diag.rawValue:
            // The gateway confirms every request first (control 0x0002, echo).
            send(box, HSFZFrame(control: HSFZControl.ack.rawValue,
                                body: Array(frame.body.prefix(7))).encoded())
            guard frame.body.count >= 2 else { return }
            let src = frame.body[0]
            let dst = frame.body[1]
            let uds = Array(frame.body.dropFirst(2))
            let functional = dst == BMWAddresses.functional
            let targets = functional ? modules.keys.sorted() : (modules[dst] != nil ? [dst] : [])
            for address in targets {
                var module = modules[address]!
                let answer = self.answer(module: &module, request: uds, functional: functional)
                modules[address] = module
                if let answer {
                    send(box, HSFZFrame.diag(src: address, dst: src, uds: answer).encoded())
                }
            }
        case HSFZControl.ident.rawValue:
            send(box, HSFZFrame(control: HSFZControl.ident.rawValue, body: identification).encoded())
        case HSFZControl.alive.rawValue:
            send(box, HSFZFrame(control: HSFZControl.alive.rawValue,
                                body: [0x00, BMWAddresses.tester]).encoded())
        default:
            break
        }
    }

    // MARK: UDS

    private func neg(_ sid: UInt8, _ nrc: UInt8) -> [UInt8] { [0x7F, sid, nrc] }

    private func answer(module: inout Module, request: [UInt8], functional: Bool) -> [UInt8]? {
        guard let sid = request.first else { return nil }
        let result: [UInt8]?
        switch sid {
        case 0x10 where request.count >= 2:
            module.session = request[1] & 0x7F
            if module.session == 1 { module.unlocked = false }
            result = request[1] & 0x80 != 0 ? nil : [0x50, module.session, 0x00, 0x32, 0x01, 0xF4]
        case 0x11 where request.count >= 2:
            module.session = 1
            module.unlocked = false
            result = request[1] & 0x80 != 0 ? nil : [0x51, request[1] & 0x7F]
        case 0x22:
            result = readDIDs(module: &module, request)
        case 0x2E where request.count >= 4:
            result = writeDID(module: &module, request)
        case 0x27 where request.count >= 2:
            result = security(module: &module, request)
        case 0x3E where request.count >= 2:
            result = request[1] & 0x80 != 0 ? nil : [0x7E, 0x00]
        case 0x14:
            result = [0x54]
        case 0x19:
            result = [0x59, 0x02, 0xFF]
        default:
            result = neg(sid, 0x11)
        }
        // Functional requests: modules keep quiet instead of saying "not supported".
        if functional, let answer = result, answer[0] == 0x7F,
           answer[2] == 0x11 || answer[2] == 0x12 || answer[2] == 0x31 {
            return nil
        }
        return result
    }

    private func readDIDs(module: inout Module, _ request: [UInt8]) -> [UInt8]? {
        guard request.count >= 3, (request.count - 1) % 2 == 0 else { return neg(0x22, 0x13) }
        var answer: [UInt8] = [0x62]
        var any = false
        var index = 1
        while index + 1 < request.count {
            let did = UInt16(request[index]) << 8 | UInt16(request[index + 1])
            let data: [UInt8]?
            switch did {
            case 0xF186: data = [module.session]
            case 0xF100: data = [module.session, 0, 0, 0]
            default: data = module.dids[did]
            }
            if let data {
                answer += Bytes.u16be(did)
                answer += data
                any = true
            }
            index += 2
        }
        return any ? answer : neg(0x22, 0x31)
    }

    private func writeDID(module: inout Module, _ request: [UInt8]) -> [UInt8]? {
        let did = UInt16(request[1]) << 8 | UInt16(request[2])
        if module.requiresSecurityForWrite {
            if module.session != UDS.extendedSession { return neg(0x2E, 0x7F) }
            if !module.unlocked { return neg(0x2E, 0x33) }
        }
        module.dids[did] = Array(request.dropFirst(3))
        return [0x6E, request[1], request[2]]
    }

    private func security(module: inout Module, _ request: [UInt8]) -> [UInt8]? {
        let level = request[1]
        if level & 1 == 1 {
            let seed = module.unlocked ? [UInt8](repeating: 0, count: 8) : Self.randomSeed()
            seeds[module.address] = seed
            return [0x67, level] + seed
        }
        guard let seed = seeds[module.address],
              let expected = MockCarAlgorithm().key(forSeed: seed, level: level, ecu: module.address),
              Array(request.dropFirst(2)) == expected else {
            return neg(0x27, 0x35)
        }
        module.unlocked = true
        return [0x67, level]
    }

    private static func randomSeed() -> [UInt8] {
        (0..<8).map { _ in UInt8.random(in: 1...255) }
    }
}



