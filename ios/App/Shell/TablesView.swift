import SwiftUI

struct TablesView: View {
    @Environment(TSClient.self) private var client
    @State private var metadata: TSMetadata?
    @State private var loading = false
    @State private var error: String?
    @State private var selected: TSMetadata.Table?

    var body: some View {
        ZStack {
            Theme.Color.paper.ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selected) { table in
            NavigationStack { RowsView(table: table) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if client.config == nil {
            EmptyState(title: "not configured",
                       detail: "Open Settings to enter your SeaTable server URL + API token.",
                       systemImage: "link.badge.plus")
        } else if loading && metadata == nil {
            LoadingState("exchanging access token…")
        } else if let error, metadata == nil {
            ErrorState(title: "couldn't reach base", detail: error,
                       retry: { Task { await load() } })
        } else if let md = metadata {
            loaded(md)
        }
    }

    private func loaded(_ md: TSMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                PromptHeader(["base", client.activeBase?.app_name ?? "—"])
                Text("Tables")
                    .font(Theme.Font.display).foregroundStyle(Theme.Color.ink)
                Card(title: "\(md.metadata.tables.count) tables", systemImage: "tablecells") {
                    VStack(spacing: 0) {
                        ForEach(md.metadata.tables) { t in
                            Button { selected = t } label: {
                                ListRow(
                                    title: t.name,
                                    metadata: "\(t.columns.count) columns",
                                    leading: { Image(systemName: "tablecells").foregroundStyle(Theme.Color.accent) },
                                    trailing: {
                                        Image(systemName: "chevron.right")
                                            .font(Theme.Font.mono).foregroundStyle(Theme.Color.faint)
                                    }
                                )
                            }.buttonStyle(.plain)
                            if t.id != md.metadata.tables.last?.id {
                                Divider().background(Theme.Color.hairline)
                            }
                        }
                    }
                }
            }.padding(Theme.Space.lg)
        }
    }

    private func load() async {
        guard client.config != nil else { return }
        loading = true; error = nil
        do { metadata = try await client.metadata() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }
}

// MARK: - Rows view

struct RowsView: View {
    let table: TSMetadata.Table
    @Environment(TSClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [[String: TSJSON]] = []
    @State private var loading = false
    @State private var error: String?
    @State private var query: String = ""

    var body: some View {
        ZStack {
            Theme.Color.paper.ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }.font(Theme.Font.mono)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && rows.isEmpty {
            LoadingState("fetching rows…")
        } else if let error, rows.isEmpty {
            ErrorState(title: "couldn't fetch", detail: error, retry: { Task { await load() } })
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    MonoLabel("~/base/\(table.name)", color: Theme.Color.faint)
                    Text(table.name).font(Theme.Font.display).foregroundStyle(Theme.Color.ink)
                }
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.Color.faint)
                    TextField("filter rows (any column)", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.monoBody).foregroundStyle(Theme.Color.ink)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                .padding(Theme.Space.sm)
                .background(Theme.Color.surface)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(Theme.Color.hairline, lineWidth: 1))
                if filteredRows.isEmpty {
                    EmptyState(title: "no rows", systemImage: "tray").frame(maxHeight: .infinity)
                } else {
                    ScrollView([.horizontal, .vertical]) { gridView }
                }
            }.padding(Theme.Space.lg)
        }
    }

    private var filteredRows: [[String: TSJSON]] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return rows }
        return rows.filter { row in
            row.values.contains { $0.display.lowercased().contains(q) }
        }
    }

    private var gridView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(table.columns) { col in
                    Text(col.name)
                        .font(Theme.Font.mono).foregroundStyle(Theme.Color.faint)
                        .padding(.horizontal, Theme.Space.sm).padding(.vertical, Theme.Space.xs)
                        .frame(width: columnWidth(for: col.type), alignment: .leading)
                        .background(Theme.Color.paper)
                }
            }
            Divider().background(Theme.Color.hairline)
            ForEach(filteredRows.indices, id: \.self) { rowIdx in
                let row = filteredRows[rowIdx]
                HStack(spacing: 0) {
                    ForEach(table.columns) { col in
                        cell(row: row, column: col)
                            .padding(.horizontal, Theme.Space.sm).padding(.vertical, Theme.Space.xs)
                            .frame(width: columnWidth(for: col.type), alignment: .leading)
                    }
                }
                Divider().background(Theme.Color.hairline)
            }
        }
        .background(Theme.Color.surface)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
            .strokeBorder(Theme.Color.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    @ViewBuilder
    private func cell(row: [String: TSJSON], column: TSMetadata.Column) -> some View {
        // Cells may be keyed by column key OR column name depending on server version.
        let value = row[column.key] ?? row[column.name] ?? .null
        if column.type == "checkbox" {
            if case .bool(let b) = value {
                Image(systemName: b ? "checkmark.square.fill" : "square")
                    .foregroundStyle(Theme.Color.accent)
            } else {
                MonoLabel("", color: Theme.Color.faint)
            }
        } else {
            Text(value.display)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Color.ink)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func columnWidth(for type: String) -> CGFloat {
        switch type {
        case "checkbox":           70
        case "number", "date":     140
        case "long-text":          280
        case "single-select",
             "multiple-select":    160
        default:                   180
        }
    }

    private func load() async {
        loading = true; error = nil
        do { rows = try await client.rows(table: table.name) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }
}
