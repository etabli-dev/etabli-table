import Foundation
@main struct CheckClient {
    @MainActor static func main() async throws {
        let domain = "etabli-client-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let client = TSClient(session: fixtureSession(), defaults: defaults)
        let uuid = "5c264e76-0e5a-448a-9f34-580b551364ca"
        func token(_ root: String, _ value: String) -> String { "{\"access_token\":\"\(value)\",\"dtable_uuid\":\"\(uuid)\",\"dtable_server\":\"https://fixture.invalid/\(root)/\"}" }
        FixtureProtocol.replies = [(200, token("api-gateway", "original"))]
        try await client.configure(apiBase: URL(string: "https://fixture.invalid/seatable")!, apiToken: "secret")
        precondition(FixtureProtocol.requests.last!.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        FixtureProtocol.replies = [(403, "{}"), (200, token("moved/api-gateway", "fresh")), (200, #"{"metadata":{"tables":[{"name":"Tasks","columns":[]}]}}"#)]
        let metadata = try await client.metadata()
        precondition(metadata.metadata.tables.first?.name == "Tasks")
        precondition(FixtureProtocol.requests.last!.url!.path == "/moved/api-gateway/api/v2/dtables/\(uuid)/metadata")
        precondition(FixtureProtocol.requests.last!.value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
        FixtureProtocol.replies = [(200, #"{"rows":[{"_id":"row","Title":"Test"}]}"#)]
        let rows = try await client.rows(table: "A & B")
        precondition(rows.first?["Title"]?.display == "Test")
        let before = client.config
        FixtureProtocol.replies = [(403, "{}")]
        do { try await client.configure(apiBase: URL(string: "https://wrong.invalid")!, apiToken: "bad"); fatalError("Failed account replaced") } catch { precondition(client.config == before) }
        FixtureProtocol.replies = [(401, "{}"), (200, token("api-gateway", "fresh")), (401, "{}")]
        do { _ = try await client.metadata(); fatalError("Retry failure hidden") } catch { precondition(FixtureProtocol.replies.isEmpty) }
        let legacy = try JSONDecoder().decode(TSAccessTokenResponse.self, from: Data(token("dtable-server", "legacy").utf8))
        let legacyURL = try TSClient.baseURL(legacy, resource: "metadata")
        precondition(legacyURL.path == "/dtable-server/api/v1/dtables/\(uuid)/metadata")
        try await checkTransportBounds()
        print("SeaTable client: gateway/legacy paths, refreshed destination, row decoding and bounded retries passed")
    }
}
