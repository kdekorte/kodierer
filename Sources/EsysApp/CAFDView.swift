import SwiftUI
import UniformTypeIdentifiers
import EsysCore

/// Tab 3 — browse a CAFD: parameters, values, current state, queue changes.
struct CAFDView: View {
    @EnvironmentObject var model: AppModel
    @State private var searchText = ""
    @State private var showCAFDImporter = false
    @State private var showNamesImporter = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBanner()
            if model.cafd != nil {
                browser
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text("Browse a CAFD").font(.title3)
            Text("Open a decrypted CAFD XML (plain or gzip — e.g. from OpenCAFDMap) to see every parameter, its byte offsets, values and coding rules. Add a community names TSV for readable names.")
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
            HStack {
                Button("Open CAFD…") { showCAFDImporter = true }
                Button("Load demo CAFD + names") { model.loadDemoDefinitions() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showCAFDImporter, allowedContentTypes: [.xml, .gzip, .data]) { result in
            if case .success(let url) = result { model.loadCAFD(url: url) }
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            header
            List(rows) { row in
                CAFDFunctionRowView(row: row)
            }
            .listStyle(.inset)
            QueueBar()
        }
        .fileImporter(isPresented: $showCAFDImporter, allowedContentTypes: [.xml, .gzip, .data]) { result in
            if case .success(let url) = result { model.loadCAFD(url: url) }
        }
        .fileImporter(isPresented: $showNamesImporter, allowedContentTypes: [UTType.tsvFile, .plainText]) { result in
            if case .success(let url) = result { model.loadNames(url: url) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.cafdFileName).font(.headline)
                Text("\(model.cafd?.datagroups.count ?? 0) sections · \(model.cafd?.functionCount ?? 0) functions")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            TextField("Series", text: $model.cafdSeries)
                .textFieldStyle(.roundedBorder).frame(width: 80)
                .onSubmit { model.reloadCAFD() }
            Button("Resolve") { model.reloadCAFD() }
            Button("Names…") { showNamesImporter = true }
            Button("Open…") { showCAFDImporter = true }
        }
        .padding()
    }

    /// Flat, searchable list of every function with its resolved name.
    private var rows: [CAFDFunctionRow] {
        guard let cafd = model.cafd else { return [] }
        var all: [CAFDFunctionRow] = []
        for datagroup in cafd.datagroups {
            for function in datagroup.functions {
                let name = model.names?.functionName(datagroup: datagroup, function: function)
                    ?? function.placeholderName
                all.append(CAFDFunctionRow(
                    id: "\(datagroup.address)-\(function.index)-\(function.start)-\(function.end)",
                    datagroup: datagroup, function: function, matchedName: name))
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.matchedName.lowercased().contains(query)
                || String(format: "%04X", $0.datagroup.address).lowercased().contains(query)
        }
    }
}

/// Value type for the flat function list.
struct CAFDFunctionRow: Identifiable {
    let id: String
    let datagroup: CAFD.Datagroup
    let function: CAFD.Function
    let matchedName: String
}
