package com.raban.etabli.table.net
import kotlinx.coroutines.flow.first
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class TSClientTest {
    private val uuid = "5c264e76-0e5a-448a-9f34-580b551364ca"
    private fun token(server: MockWebServer, path: String = "/api-gateway/", value: String = "access") = MockResponse().setBody("""{"access_token":"$value","dtable_uuid":"$uuid","dtable_server":"${server.url(path)}"}""")
    @Test fun usesReturnedGatewayAndRefreshesOnceWithTheNewDestination() = service { server, client ->
        server.enqueue(token(server))
        client.configure(server.url("/seatable").toString(), "api-secret")
        val exchange = server.takeRequest()
        assertEquals("/seatable/api/v2.1/dtable/app-access-token/", exchange.path)
        assertEquals("Bearer api-secret", exchange.getHeader("Authorization"))
        server.enqueue(MockResponse().setResponseCode(403))
        server.enqueue(token(server, "/new/api-gateway/", "fresh"))
        server.enqueue(MockResponse().setBody("""{"metadata":{"tables":[{"name":"Tasks","columns":[{"key":"title","name":"Title","type":"text"}]}]}}"""))
        assertEquals("Tasks", client.metadata().tables.single().name)
        assertEquals("/api-gateway/api/v2/dtables/$uuid/metadata/", server.takeRequest().path)
        assertEquals("/seatable/api/v2.1/dtable/app-access-token/", server.takeRequest().path)
        val retry = server.takeRequest()
        assertEquals("/new/api-gateway/api/v2/dtables/$uuid/metadata/", retry.path)
        assertEquals("Bearer fresh", retry.getHeader("Authorization"))
        server.enqueue(MockResponse().setBody("""{"rows":[{"_id":"r1","title":"Work"}]}"""))
        assertEquals("Work", client.rows("A & B").single().getString("title"))
        assertEquals("A & B", server.takeRequest().requestUrl!!.queryParameter("table_name"))
    }
    @Test fun supportsLegacyRootsAndKeepsExistingAccountOnFailedConfigure() = service { server, client ->
        server.enqueue(token(server, "/dtable-server/"))
        client.configure(server.url("/").toString(), "secret")
        server.takeRequest()
        server.enqueue(MockResponse().setBody("""{"metadata":{"tables":[]}}"""))
        assertTrue(client.metadata().tables.isEmpty())
        assertEquals("/dtable-server/api/v1/dtables/$uuid/metadata/", server.takeRequest().path)
        val before = client.configFlow.first()
        server.enqueue(MockResponse().setResponseCode(403))
        try { client.configure(server.url("/wrong").toString(), "bad"); fail("Bad account accepted") } catch (_: TSError.Http) { }
        assertEquals(before, client.configFlow.first())
        server.enqueue(MockResponse().setBody("{}"))
        try { client.rows("Tasks"); fail("Missing rows accepted") } catch (_: TSError.Decoding) { }
    }
    @Test fun boundsAuthenticationRetriesAndRefusesInsecureGateway() = service { server, client ->
        server.enqueue(token(server))
        client.configure(server.url("/").toString(), "secret")
        server.enqueue(MockResponse().setResponseCode(401))
        server.enqueue(token(server))
        server.enqueue(MockResponse().setResponseCode(401))
        try { client.metadata(); fail("Authentication error hidden") } catch (e: TSError.Http) { assertEquals(401, e.status) }
        assertEquals(4, server.requestCount)
        server.enqueue(MockResponse().setBody("""{"access_token":"secret","dtable_uuid":"$uuid","dtable_server":"http://example.org"}"""))
        try { client.configure(server.url("/").toString(), "new"); fail("Insecure gateway accepted") } catch (_: TSError.Decoding) { }
    }
}
