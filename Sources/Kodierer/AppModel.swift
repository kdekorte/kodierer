import SwiftUI
import KodiererCore

/// All app state: connection, vehicle scan, coding backup, loaded definitions.
/// One instance lives in `MainTabs` and is injected as an environment object.
@MainActor
final class AppModel: ObservableObject {

    // MARK: Connection

    enum Mode: String, CaseIterable, Identifiable {
        case demo = "Demo car"
        case real = "Real car"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .demo
    @Published var host = ""
    @Published var busy = ""

    // MARK: Vehicle

    @Published var discovering = false
    @Published var scanning = false
    @Published var advertisements: [VehicleAdvertisement] = []
    @Published var probedHosts: [String] = []
    @Published var identity: VehicleIdentity?
    @Published var modules: [ECUInfo] = []

    // MARK: Coding

    @Published var backup: CodingBackup?
    @Published var reading = false
    @Published var applying = false
    @Published var queue: [PendingChange] = []

    // MARK: Loaded definitions

    @Published var cheatEntries: [CheatEntry] = []
    @Published var cafd: CAFD?
    @Published var cafdData: Data?
    @Published var cafdFileName = ""
    @Published var cafdSeries = "F025"
    @Published var names: CAFDNames?
    /// Plain-language option descriptions, keyed by function name.
    @Published var descriptions: OptionDescriptions?

    // MARK: Feedback / session log

    @Published var message: String?
    @Published var errorText: String?
    /// Chronological log of every connection, read and write action this session.
    @Published private(set) var actionLog: [String] = []

    var session: VehicleSession?
    private(set) var mockCar: MockCar?
    var securityAlgorithm: (any SecurityAlgorithm)?

    init() {
        loadDataFolder()
    }

    var isConnected: Bool { session != nil }

    /// nil once the Mac has a 169.254.x.x address (ENET link up).
    var linkLocalHint: String? {
        NetworkInterfaces.linkLocalAddresses().isEmpty
            ? "No 169.254.x.x address yet — plug the ENET cable in, set the adapter to DHCP and wait ~30 s (a self-assigned IP is good)."
            : nil
    }

    func showMessage(_ text: String) { message = text; errorText = nil }
    func showError(_ error: Error) { errorText = String(describing: error); message = nil }
    func clearFeedback() { message = nil; errorText = nil }

    /// Appends a timestamped line to the session log (kept for the whole run).
    func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        actionLog.append("\(stamp)  \(line)")
        if actionLog.count > 500 { actionLog.removeFirst(actionLog.count - 500) }
    }

    // MARK: Connection

    /// One click: virtual car + connect + identify + scan + read HU_NBT coding.
    func startDemo() async {
        clearFeedback()
        busy = "Starting virtual car…"
        do {
            let car = MockCar()
            try await car.start()
            let connection = HSFZConnection()
            try await connection.connect(to: "127.0.0.1", port: car.port)
            mockCar = car
            let session = VehicleSession(transport: connection)
            self.session = session
            securityAlgorithm = MockCarAlgorithm()
            mode = .demo
            identity = await session.readIdentity()
            busy = "Scanning…"
            modules = await session.scanSVT(range: 0x10...0x70, dwell: 0.08) { [weak self] found in
                Task { @MainActor in self?.modules.append(found) }
            }
            if let hu = SVTScan.find(named: "HU_NBT", in: modules) {
                busy = "Reading HU_NBT coding…"
                backup = try await session.readCoding(ecu: hu.address, ecuName: hu.name)
            }
            busy = ""
            showMessage("Virtual car is up (VIN \(identity?.vin ?? "?"), \(modules.count) modules) and HU_NBT coding is read in. Switch to Coding or CAFD.")
            log("Demo: connected virtual car, VIN \(identity?.vin ?? "?"), \(modules.count) modules, read \(backup?.sections.count ?? 0) sections from HU_NBT")
        } catch {
            busy = ""
            showError(error)
        }
    }

    func discover() async {
        clearFeedback()
        discovering = true
        advertisements = []
        probedHosts = []
        let found = await HSFZDiscovery.findCars(timeout: 2)
        advertisements = found
        if found.isEmpty {
            probedHosts = await HSFZDiscovery.probeCandidates(timeout: 0.4)
        }
        discovering = false
        if found.isEmpty && probedHosts.isEmpty {
            showMessage("No car answered. Check ignition and cable, then try again — or type the gateway IP by hand.")
        }
    }

    func connectAndScan() async {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { showMessage("Enter the gateway IP first."); return }
        clearFeedback()
        busy = "Connecting to \(host)…"
        do {
            let connection = HSFZConnection()
            try await connection.connect(to: host, port: HSFZConnection.defaultPort)
            let session = VehicleSession(transport: connection)
            self.session = session
            securityAlgorithm = nil      // real HU_NBT algorithm still open (PROTOCOL.md §5)
            mockCar = nil
            busy = "Reading identity…"
            identity = await session.readIdentity()
            busy = "Scanning modules — this can take a minute…"
            scanning = true
            modules = await session.scanSVT(range: 0x10...0xF9, dwell: 0.25) { [weak self] found in
                Task { @MainActor in self?.modules.append(found) }
            }
            scanning = false
            busy = ""
            showMessage("VIN \(identity?.vin ?? "?"), I-Step \(identity?.iStepText.first ?? "?") — \(modules.count) modules found.")
            log("Connected to \(host): VIN \(identity?.vin ?? "?"), \(modules.count) modules")
        } catch {
            scanning = false
            busy = ""
            session = nil
            showError(error)
        }
    }

    func disconnect() {
        session?.transport.close()
        session = nil
        mockCar?.stop()
        mockCar = nil
        identity = nil
        modules = []
        queue = []
        busy = ""
        log("Disconnected")
        showMessage("Disconnected.")
    }

    // MARK: Reading

    func readCoding(_ module: ECUInfo) async {
        guard let session else { showMessage("Not connected."); return }
        clearFeedback()
        reading = true
        do {
            backup = try await session.readCoding(ecu: module.address, ecuName: module.name)
            log("Read coding from \(module.displayName): \(backup?.sections.count ?? 0) sections, \(backup?.sections.reduce(0) { $0 + $1.bytes.count } ?? 0) bytes")
            showMessage("Read \(backup?.sections.count ?? 0) sections from \(module.displayName) — continue in the Coding tab.")
        } catch {
            showError(error)
        }
        reading = false
    }

    func rereadCoding() async {
        guard let backup, modules.contains(where: { Int($0.address) == backup.ecuAddress }) else {
            showMessage("The module of this backup is not in the scan list — connect first.")
            return
        }
        let module = modules.first { Int($0.address) == backup.ecuAddress }!
        await readCoding(module)
    }
}
