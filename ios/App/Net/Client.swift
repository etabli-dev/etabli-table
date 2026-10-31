// Copyright 2026 R. Heller
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

// SeaTable client.
//
// Auth model is two-tier:
//   1. Long-lived **API-Token** for a base (the user generates this in
//      SeaTable → Base → Advanced → API Tokens). Stored in Keychain.
//   2. Short-lived **Base-Token** obtained by GET-ing
//      `/api/v2.1/dtable/app-access-token/` with `Authorization: Token <API-Token>`.
//      Cached in memory; auto-refreshed on 401. Each base also returns the
//      dtable server URL + dtable_uuid which we use for row endpoints.
//
// Verified shapes against api.seatable.com docs at construction time.

public struct TSConfig: Equatable, Sendable {
    public var apiBase: URL
    public var hasToken: Bool
    public var revision = UUID()
}

public enum TSError: Error, LocalizedError {
    case notConfigured
    case http(status: Int, body: String?)
    case decoding(String)
    case transport(String)
    case noActiveBase
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Configure base URL + API token in Settings."
        case .http(let s, _): "Server returned HTTP \(s)."
        case .decoding(let m): "Couldn't decode response: \(m)."
        case .transport(let m): "Network error: \(m)."
        case .noActiveBase: "Pick a base to load tables."
        }
    }
}

public struct TSAccessTokenResponse: Decodable, Sendable {
    public let app_name: String?
    public let access_token: String
    public let dtable_uuid: String
    public let dtable_server: String?
    public let workspace_id: Int?
    public let use_api_gateway: Bool?
}

public struct TSMetadata: Decodable, Sendable {
    public let metadata: Payload
    public struct Payload: Decodable, Sendable {
        public let tables: [Table]
    }
    public struct Table: Decodable, Identifiable, Sendable {
        public var id: String { _id ?? name }
        public let _id: String?
        public let name: String
        public let columns: [Column]
    }
    public struct Column: Decodable, Identifiable, Sendable {
        public var id: String { key }
        public let key: String
        public let name: String
        public let type: String
    }
}

public enum TSJSON: Decodable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), array([TSJSON]), object([String: TSJSON]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let a = try? c.decode([TSJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: TSJSON].self) { self = .object(o); return }
        self = .null
    }
    public var display: String {
        switch self {
        case .string(let s): s
        case .number(let n):
            n.rounded() == n && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): b ? "✓" : ""
        case .array(let a): a.map(\.display).joined(separator: ", ")
        case .object(let o): o.map { "\($0.key): \($0.value.display)" }.joined(separator: ", ")
        case .null: ""
        }
    }
}

@MainActor
@Observable
public final class TSClient {

    public private(set) var config: TSConfig?
    public private(set) var activeBase: TSAccessTokenResponse?
    private let session: ClientHTTP
    private let defaults: UserDefaults
    private var connectionIntent = UUID()
    private let decoder = JSONDecoder()
    private let keychainService = "tablesync.seatable"
    private let urlKey = "tablesync.seatable.baseurl"

    public init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = ClientHTTP(configuration: session.configuration)
        self.defaults = defaults
        if let saved = (try? Keychain.get(service: keychainService, account: "connection.v2")) ?? nil {
            guard let value = try? JSONDecoder().decode(StoredConnection.self, from: Data(saved.utf8)),
                  (try? secureServer(value.server)) != nil, !value.token.isEmpty else { return }
            self.config = TSConfig(apiBase: value.server, hasToken: true)
            return
        }
        if let stored = defaults.url(forKey: urlKey), (try? secureServer(stored)) != nil,
           let token = (try? Keychain.get(service: keychainService, account: "api-token")) ?? nil,
           !token.isEmpty {
            self.config = TSConfig(apiBase: stored, hasToken: true)
        }
    }

    @discardableResult
    public func configure(apiBase: URL, apiToken: String) async throws -> TSAccessTokenResponse {
        let intent = UUID(); connectionIntent = intent
        let base = try secureServer(apiBase)
        guard !apiToken.isEmpty else { throw TSError.notConfigured }
        let access = try await exchange(base: base, token: apiToken)
        guard connectionIntent == intent else { throw CancellationError() }
        let saved = try JSONEncoder().encode(StoredConnection(server: base, token: apiToken))
        try Keychain.set(String(decoding: saved, as: UTF8.self), service: keychainService, account: "connection.v2")
        defaults.set(base, forKey: urlKey)
        config = TSConfig(apiBase: base, hasToken: true)
        activeBase = access
        return access
    }

    public func disconnect() throws {
        connectionIntent = UUID()
        try Keychain.delete(service: keychainService, account: "api-token")
        try Keychain.delete(service: keychainService, account: "connection.v2")
        defaults.removeObject(forKey: urlKey)
        config = nil
        activeBase = nil
    }

    private func apiToken() throws -> String {
        if let saved = try Keychain.get(service: keychainService, account: "connection.v2") {
            let value = try JSONDecoder().decode(StoredConnection.self, from: Data(saved.utf8))
            guard value.server == config?.apiBase else { throw TSError.notConfigured }
            return value.token
        }
        guard let t = try Keychain.get(service: keychainService, account: "api-token"), !t.isEmpty
        else { throw TSError.notConfigured }
        return t
    }

    // MARK: - Base-token exchange + caching

    /// Cached base token; refreshed on demand or after a 401.
    @discardableResult
    public func ensureBaseToken(forceRefresh: Bool = false) async throws -> TSAccessTokenResponse {
        if !forceRefresh, let active = activeBase { return active }
        guard let cfg = config else { throw TSError.notConfigured }
        let expected = config
        let access = try await exchange(base: cfg.apiBase, token: apiToken())
        guard config == expected else { throw CancellationError() }
        activeBase = access
        return access
    }

    private func exchange(base: URL, token: String) async throws -> TSAccessTokenResponse {
        var request = URLRequest(url: try secureServer(base).appendingPathComponent("api/v2.1/dtable/app-access-token/"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        do {
            let access = try decoder.decode(TSAccessTokenResponse.self, from: data)
            _ = try Self.baseURL(access, resource: "metadata")
            return access
        } catch { throw TSError.decoding(error.localizedDescription) }
    }

    static func baseURL(_ access: TSAccessTokenResponse, resource: String) throws -> URL {
        guard !access.access_token.isEmpty, UUID(uuidString: access.dtable_uuid) != nil,
              let raw = access.dtable_server, let url = URL(string: raw) else { throw TSError.decoding("Invalid base token response") }
        let server = try secureServer(url)
        let version = access.use_api_gateway == true || server.path.hasSuffix("/api-gateway") ? "v2" : "v1"
        return server.appendingPathComponent("api/\(version)/dtables/\(access.dtable_uuid)/\(resource)/")
    }

    // MARK: - Metadata + rows

    public func metadata() async throws -> TSMetadata {
        try await dtableGet(resource: "metadata", as: TSMetadata.self)
    }

    public struct RowsResponse: Decodable, Sendable { public let rows: [[String: TSJSON]] }

    public func rows(table: String, limit: Int = 500) async throws -> [[String: TSJSON]] {
        guard !table.isEmpty && (1...1000).contains(limit) else { throw TSError.decoding("Select a table and a row limit from 1 to 1000") }
        let payload = try await dtableGet(resource: "rows", query: [URLQueryItem(name: "table_name", value: table), URLQueryItem(name: "limit", value: String(limit))], as: RowsResponse.self)
        return payload.rows
    }

    /// Batch-append rows. SeaTable's row endpoints accept batches in a
    /// single POST — we never call the per-row endpoint in a loop.
    public func appendRows(table: String, rows: [[String: TSJSON]]) async throws {
        let token = try await ensureBaseToken()
        let gateway = token.use_api_gateway == true || URL(string: token.dtable_server ?? "")?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("api-gateway") == true
        let url = try Self.baseURL(token, resource: gateway ? "rows" : "batch-append-rows")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token.access_token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "table_name": table,
            "rows": rows.map { dict -> [String: Any] in
                Dictionary(uniqueKeysWithValues: dict.map { ($0.key, jsonValue($0.value)) })
            }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
    }

    // MARK: - Generic dtable GET with 401-refresh

    private func dtableGet<T: Decodable>(resource: String, query: [URLQueryItem] = [], as: T.Type) async throws -> T {
        let expected = config
        for attempt in 0...1 {
            let token = try await ensureBaseToken(forceRefresh: attempt == 1)
            guard config == expected else { throw CancellationError() }
            var components = URLComponents(url: try Self.baseURL(token, resource: resource), resolvingAgainstBaseURL: false)!
            if !query.isEmpty { components.queryItems = query }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token.access_token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard config == expected else { throw CancellationError() }
            if attempt == 0, let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) { continue }
            try Self.check(response, data: data)
            do { return try decoder.decode(T.self, from: data) }
            catch { throw TSError.decoding(error.localizedDescription) }
        }
        throw TSError.transport("Authentication retry exhausted")
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TSError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TSError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    private func jsonValue(_ v: TSJSON) -> Any {
        switch v {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b
        case .array(let a): a.map { jsonValue($0) }
        case .object(let o): o.mapValues { jsonValue($0) }
        case .null: NSNull()
        }
    }
}
