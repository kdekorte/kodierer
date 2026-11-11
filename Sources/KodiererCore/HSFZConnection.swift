import Foundation
import Network

/// TCP connection to a BMW F-series gateway (ZGW) speaking HSFZ on port 6801.
///
/// - One request is on the wire at a time; others wait in a FIFO queue.
/// - Gateway ack frames (control 0x0002) are skipped.
/// - Replies are matched to requests by source address plus UDS echo bytes.
/// - `0x78 responsePending` keeps a request alive until its overall deadline.
/// - The gateway allows one tester at a time; a second connection is reset.
public final class HSFZConnection: DiagTransport {
    public static let defaultPort: UInt16 = 6801
    public let testerAddress: UInt8 = BMWAddresses.tester

    /// Optional trace, called with one line per frame.
    public var trace: ((String) -> Void)?
    /// Called once when the connection drops.
    public var onDrop: ((Error) -> Void)?

    private enum State { case new, open, dead }

    private final class Job {
        let ecu: UInt8
        let uds: [UInt8]
        let initialTimeout: TimeInterval
        let deadline: Date
        let continuation: CheckedContinuation<[UInt8], Error>
        var timer: DispatchSourceTimer?

        init(ecu: UInt8, uds: [UInt8], initialTimeout: TimeInterval, deadline: Date,
             continuation: CheckedContinuation<[UInt8], Error>) {
            self.ecu = ecu; self.uds = uds; self.initialTimeout = initialTimeout
            self.deadline = deadline; self.continuation = continuation
        }
    }

    private let queue = DispatchQueue(label: "kodierer.hsfz.connection")
    private var connection: NWConnection?
    private var state: State = .new
    private var rx: [UInt8] = []
    private var current: Job?
    private var waiting: [Job] = []
    private var keepAliveTimer: DispatchSourceTimer?

    public init() {}

    public var isOpen: Bool { queue.sync { state == .open } }

    // MARK: Connecting

    public func connect(to host: String,
                        port: UInt16 = HSFZConnection.defaultPort,
                        timeout: TimeInterval = 4) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.state == .new else {
                    cont.resume(throwing: TransportError.alreadyUsed); return
                }
                guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                    cont.resume(throwing: TransportError.dropped("invalid port \(port)")); return
                }
                let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
                self.connection = conn
                var resumed = false
                conn.stateUpdateHandler = { [weak self] newState in
                    guard let self else { return }
                    switch newState {
                    case .ready:
                        self.state = .open
                        if !resumed { resumed = true; cont.resume() }
                        self.receiveLoop()
                    case .failed(let error):
                        if !resumed { resumed = true; cont.resume(throwing: error) }
                        self.drop(error)
                    case .cancelled:
                        let err = TransportError.connectTimeout("\(host):\(port)")
                        if !resumed { resumed = true; cont.resume(throwing: err) }
                        self.drop(err)
                    default:
                        break
                    }
                }
                conn.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if !resumed && self.state != .open {
                        resumed = true
                        conn.cancel()
                        cont.resume(throwing: TransportError.connectTimeout("\(host):\(port)"))
                    }
                }
            }
        }
    }

    /// Opens a throwaway TCP connection to check whether a gateway listens there.
    public static func probe(host: String,
                             port: UInt16 = HSFZConnection.defaultPort,
                             timeout: TimeInterval = 0.6) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        return await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let workQueue = DispatchQueue(label: "kodierer.hsfz.probe")
            var resumed = false
            let finish: (Bool) -> Void = { ok in
                guard !resumed else { return }
                resumed = true
                conn.cancel()
                cont.resume(returning: ok)
            }
            conn.stateUpdateHandler = { newState in
                switch newState {
                case .ready: finish(true)
                case .failed: finish(false)
                case .cancelled: finish(false)
                default: break
                }
            }
            conn.start(queue: workQueue)
            workQueue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    // MARK: Requests

    public func request(to ecu: UInt8, _ uds: [UInt8], timeout: TimeInterval = 2) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard self.state == .open else {
                    cont.resume(throwing: TransportError.notConnected); return
                }
                guard self.waiting.count < 128 else {
                    cont.resume(throwing: TransportError.dropped("request queue full")); return
                }
                let job = Job(ecu: ecu, uds: uds, initialTimeout: timeout,
                              deadline: Date().addingTimeInterval(max(timeout, 10)), continuation: cont)
                self.waiting.append(job)
                self.pump()
            }
        }
    }

    // MARK: Queue pump

    /// Must run on `queue`. Puts the next waiting job on the wire.
    private func pump() {
        guard current == nil, state == .open, !waiting.isEmpty else { return }
        let job = waiting.removeFirst()
        current = job
        trace?("→ \(String(job.ecu, radix: 16)) \(Bytes.hex(job.uds))")
        send(HSFZFrame.diag(src: testerAddress, dst: job.ecu, uds: job.uds).encoded())
        armTimer(job, interval: min(job.initialTimeout, max(0, job.deadline.timeIntervalSinceNow)))
    }

    private func armTimer(_ job: Job, interval: TimeInterval) {
        job.timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in self?.timedOut(job) }
        timer.resume()
        job.timer = timer
    }

    private func timedOut(_ job: Job) {
        guard current === job else { return }
        finish(job) { job.continuation.resume(throwing: UDSError.timeout(ecu: job.ecu)) }
    }

    private func finish(_ job: Job, _ settle: () -> Void) {
        job.timer?.cancel()
        job.timer = nil
        if current === job { current = nil }
        settle()
        pump()
    }

    // MARK: Receiving

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.rx.append(contentsOf: data)
                self.processBuffer()
            }
            if self.state != .open { return }
            if let error {
                self.drop(error)
            } else if isComplete {
                self.drop(TransportError.dropped("remote closed"))
            } else {
                self.receiveLoop()
            }
        }
    }

    private func processBuffer() {
        while rx.count >= HSFZFrame.headerLength {
            let frame: HSFZFrame
            do {
                guard let parsed = try HSFZFrame.parse(rx) else { return }
                frame = parsed
            } catch {
                drop(error)
                return
            }
            rx.removeFirst(HSFZFrame.headerLength + frame.body.count)
            handle(frame)
            if state != .open { return }
        }
    }

    private func handle(_ frame: HSFZFrame) {
        // Error control words (0x40 ... 0xFF): fail the current request, keep the link.
        if let error = HSFZProtocolError.from(controlWord: frame.control) {
            trace?("! \(error)")
            if let job = current {
                finish(job) { job.continuation.resume(throwing: error) }
            }
            return
        }
        if frame.isAck { return }                        // gateway echo of our request
        if frame.isAlive {                                // answer gateway keep-alive
            send(HSFZFrame(control: HSFZControl.alive.rawValue, body: [0x00, testerAddress]).encoded())
            return
        }
        if frame.isIdent { return }                       // unsolicited identification
        guard frame.isDiag, let src = frame.src, let dst = frame.dst, let payload = frame.uds else { return }
        guard let job = current, dst == testerAddress else { return }
        let functional = job.ecu == BMWAddresses.functional
        guard functional || src == job.ecu else { return }
        guard udsAnswers(request: job.uds, response: payload) else { return }
        trace?("← \(String(src, radix: 16)) \(Bytes.hex(payload))")
        if UDSResponse(raw: payload).isPending {
            let remaining = job.deadline.timeIntervalSinceNow
            if remaining > 0 {
                armTimer(job, interval: min(job.initialTimeout, remaining))
                return
            }
        }
        finish(job) { job.continuation.resume(returning: payload) }
    }

    // MARK: Lifecycle

    private func send(_ bytes: [UInt8]) {
        connection?.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            if let error { self?.drop(error) }
        })
    }

    /// Sends a functional TesterPresent while idle, so modules stay in session.
    public func startKeepAlive(interval: TimeInterval = 2) {
        queue.async {
            self.keepAliveTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in
                guard let self, self.state == .open, self.current == nil, self.waiting.isEmpty else { return }
                self.send(HSFZFrame.diag(src: self.testerAddress, dst: BMWAddresses.functional,
                                         uds: UDS.testerPresent()).encoded())
            }
            timer.resume()
            self.keepAliveTimer = timer
        }
    }

    public func close() {
        queue.async { self.drop(TransportError.dropped("closed by caller"), notify: false) }
    }

    private func drop(_ error: Error, notify: Bool = true) {
        guard state != .dead else { return }
        let wasOpen = state == .open
        state = .dead
        keepAliveTimer?.cancel()
        connection?.cancel()
        let job = current
        current = nil
        let queued = waiting
        waiting.removeAll()
        if let job {
            job.timer?.cancel()
            job.continuation.resume(throwing: error)
        }
        for job in queued {
            job.timer?.cancel()
            job.continuation.resume(throwing: error)
        }
        if notify && wasOpen { onDrop?(error) }
    }

}
