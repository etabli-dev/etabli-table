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
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let keychainService = "tablesync.seatable"
    private let urlKey = "tablesync.seatable.baseurl"

    public init(session: URLSession = .shared) {
        self.session = session
        if let stored = UserDefaults.standard.url(forKey: urlKey),
           let token = (try? Keychain.get(service: keychainService, account: "api-token")) ?? nil,
           !token.isEmpty {
            self.config = TSConfig(apiBase: stored, hasToken: true)
        }
    }

    public func configure(apiBase: URL, apiToken: String) throws {
        UserDefaults.standard.set(apiBase, forKey: urlKey)
        try Keychain.set(apiToken, service: keychainService, account: "api-token")
        config = TSConfig(apiBase: apiBase, hasToken: true)
        activeBase = nil
    }

    public func disconnect() throws {
        try Keychain.delete(service: keychainService, account: "api-token")
        UserDefaults.standard.removeObject(forKey: urlKey)
        config = nil
        activeBase = nil
    }

    private func apiToken() throws -> String {
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
        let url = cfg.apiBase.appendingPathComponent("api/v2.1/dtable/app-access-token/")
        var req = URLRequest(url: url)
        req.setValue("Token \(try apiToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data: data)
        do {
            let resp = try decoder.decode(TSAccessTokenResponse.self, from: data)
            activeBase = resp
            return resp
        } catch { throw TSError.decoding(error.localizedDescription) }
    }

    // MARK: - Metadata + rows

    public func metadata() async throws -> TSMetadata {
        let token = try await ensureBaseToken()
        guard let serverString = token.dtable_server,
              let server = URL(string: serverString) else {
            throw TSError.transport("No dtable_server returned from token exchange")
        }
        let url = server.appendingPathComponent("api/v1/dtables/\(token.dtable_uuid)/metadata/")
        return try await dtableGet(url: url, accessToken: token.access_token, as: TSMetadata.self)
    }

    public struct RowsResponse: Decodable, Sendable { public let rows: [[String: TSJSON]] }

    public func rows(table: String, limit: Int = 500) async throws -> [[String: TSJSON]] {
        let token = try await ensureBaseToken()
        guard let serverString = token.dtable_server,
              let server = URL(string: serverString) else {
            throw TSError.transport("No dtable_server")
        }
        guard var comps = URLComponents(
            url: server.appendingPathComponent("api/v1/dtables/\(token.dtable_uuid)/rows/"),
            resolvingAgainstBaseURL: false
        ) else { throw TSError.transport("Couldn't build URL") }
        comps.queryItems = [
            URLQueryItem(name: "table_name", value: table),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps.url else { throw TSError.transport("Couldn't build URL") }
        let payload = try await dtableGet(url: url, accessToken: token.access_token, as: RowsResponse.self)
        return payload.rows
    }

    /// Batch-append rows. SeaTable's row endpoints accept batches in a
    /// single POST — we never call the per-row endpoint in a loop.
    public func appendRows(table: String, rows: [[String: TSJSON]]) async throws {
        let token = try await ensureBaseToken()
        guard let serverString = token.dtable_server,
              let server = URL(string: serverString) else {
            throw TSError.transport("No dtable_server")
        }
        let url = server.appendingPathComponent("api/v1/dtables/\(token.dtable_uuid)/batch-append-rows/")
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

    private func dtableGet<T: Decodable>(url: URL, accessToken: String, as: T.Type) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // Stale base token — refresh once and retry.
            let fresh = try await ensureBaseToken(forceRefresh: true)
            var retry = req
            retry.setValue("Bearer \(fresh.access_token)", forHTTPHeaderField: "Authorization")
            let (data2, response2) = try await session.data(for: retry)
            try Self.check(response2, data: data2)
            do { return try decoder.decode(T.self, from: data2) }
            catch { throw TSError.decoding(error.localizedDescription) }
        }
        try Self.check(response, data: data)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw TSError.decoding(error.localizedDescription) }
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
