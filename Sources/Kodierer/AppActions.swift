import Foundation
import KodiererCore

extension AppModel {

    // MARK: Queue + write

    var canApply: Bool { session != nil && backup != nil && !queue.isEmpty }

    /// Line up a CAFD value as a write operation (applied via Apply to car).
    func queueSet(value: CAFD.Value, function: CAFD.Function, datagroup: CAFD.Datagroup) {
        guard let cafd else { return }
        guard let operation = cafd.operation(setting: value, of: function, in: datagroup) else {
            showMessage("This value has no bytes to write.")
            return
        }
        let functionTitle = names?.functionName(datagroup: datagroup, function: function)
            ?? function.placeholderName
        let valueTitle = names?.valueName(datagroup: datagroup, function: function, value: value)
            ?? "wert_\(String(format: "%02d", value.index))"
        queue.append(PendingChange(label: "\(functionTitle) = \(valueTitle)", operation: operation))
    }

    func applyQueue() async {
        guard let session, let backup, !queue.isEmpty else { return }
        applying = true
        do {
            let operations = queue.map(\.operation)
            let modified = try await session.applyOperations(
                operations, to: backup,
                description: queue.map(\.label).joined(separator: "; "),
                security: securityAlgorithm)
            self.backup = modified
            queue = []
            showMessage("Applied and verified — new snapshot kept in memory, save it from the Coding tab.")
        } catch {
            showError(error)
        }
        applying = false
    }

    func applyCode(_ entry: CheatEntry) async {
        guard let session, let backup else { showMessage("Connect and read coding data first."); return }
        applying = true
        do {
            self.backup = try await session.apply(entry.code, to: backup, security: securityAlgorithm)
            showMessage("Applied “\(entry.code.description)” — verified by re-read.")
        } catch {
            showError(error)
        }
        applying = false
    }

    func restoreOriginal() async {
        guard let session, let backup else { showMessage("Nothing to restore."); return }
        applying = true
        do {
            try await session.restore(backup, security: securityAlgorithm)
            showMessage("Restored the saved snapshot back to the ECU.")
        } catch {
            showError(error)
        }
        applying = false
    }

    // MARK: Files

    /// Runs `body` with access to a user-picked file (sandbox-safe on both platforms).
    private func accessing<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    func loadBackup(url: URL) {
        do {
            backup = try accessing(url) { try CodingBackup.load(from: $0) }
            showMessage("Loaded backup — \(backup?.sections.count ?? 0) sections. Applying needs a live connection; decoding works offline.")
        } catch {
            showError(error)
        }
    }

    func loadCheatSheet(url: URL) {
        do {
            let sheet = try accessing(url) { try CheatSheet.parse(url: $0) }
            appendCheatCodes(sheet.codes())
            showMessage("Loaded \(sheet.cafds.count) CAFD blocks from \(url.lastPathComponent).")
        } catch {
            showError(error)
        }
    }

    func loadCAFD(url: URL) {
        do {
            cafdData = try accessing(url) { try Data(contentsOf: $0) }
            cafdFileName = url.lastPathComponent
            reloadCAFD()
        } catch {
            showError(error)
        }
    }

    func loadNames(url: URL) {
        do {
            names = try accessing(url) { try CAFDNames.parse(url: $0) }
            showMessage("Loaded \(names?.entries.count ?? 0) name rows.")
        } catch {
            showError(error)
        }
    }

    /// Built-in synthetic definitions so every screen works with zero files.
    func loadDemoDefinitions() {
        appendCheatCodes(DemoData.cheatCodes())
        cafdData = Data(DemoData.cafdXML.utf8)
        cafdFileName = "demo-cafd.xml (built-in)"
        names = CAFDNames.parse(text: DemoData.namesTSV)
        reloadCAFD()
        showMessage("Loaded built-in demo definitions (synthetic data, no real offsets).")
    }

    /// Re-parse the CAFD with the current series text (resolves coding rules).
    func reloadCAFD() {
        guard let cafdData else { return }
        let series = cafdSeries.trimmingCharacters(in: .whitespaces)
        do {
            cafd = try CAFD.parse(data: cafdData, series: series.isEmpty ? nil : series)
        } catch {
            cafd = nil
            showError(error)
        }
    }

    private func appendCheatCodes(_ new: [FDLCheatCode]) {
        var known = Set(cheatEntries.map(\.id))
        var entries = cheatEntries
        for (index, code) in new.enumerated() {
            let id = "\(code.cafdName ?? code.cafdID ?? "—")|\(code.description)|\(index)"
            guard !known.contains(id) else { continue }
            known.insert(id)
            entries.append(CheatEntry(id: id, code: code))
        }
        cheatEntries = entries
    }

    // MARK: Decoding helpers for the views

    /// The declared value the current backup has for this function, if any.
    func currentValue(datagroup: CAFD.Datagroup, function: CAFD.Function) -> CAFD.Value? {
        guard let cafd, let backup else { return nil }
        return cafd.currentValue(of: function, in: datagroup, backup: backup)
    }

    enum CheatApplicability {
        case alreadyActive
        case wouldChange
        case notApplicable(String)
    }

    /// Would this cheat code change anything on the current backup?
    func applicability(of code: FDLCheatCode) -> CheatApplicability {
        guard let backup else { return .notApplicable("no backup loaded") }
        do {
            return try code.applied(to: backup) == backup ? .alreadyActive : .wouldChange
        } catch let error as FDLEditError {
            return .notApplicable(error.description)
        } catch {
            return .notApplicable(String(describing: error))
        }
    }
}
