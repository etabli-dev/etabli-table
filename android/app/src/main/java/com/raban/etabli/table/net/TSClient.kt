// Copyright 2026 R. Heller
// SPDX-License-Identifier: Apache-2.0

package com.raban.etabli.table.net

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONException
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

// SeaTable client.
//
// Two-token model:
//   1. user-generated long-lived API token (per-base) → encrypted in DataStore
//   2. short-lived access_token + dtable_server + dtable_uuid obtained by
//      GET /api/v2.1/dtable/app-access-token/ with the API token.
//
// Refreshed lazily — if a base call returns 401/403 we refresh & retry once.

data class TSConfig(val apiBase: String, val hasToken: Boolean, val revision: Int = 0)

sealed class TSError(message: String) : RuntimeException(message) {
    object NotConfigured : TSError("Set the server + API token in Settings.")
    class Http(val status: Int, val body: String?) : TSError("Server returned HTTP $status.")
    class Decoding(msg: String) : TSError("Couldn't decode response: $msg.")
    class Transport(msg: String) : TSError("Network error: $msg.")
}

data class TSAccess(
    val appName: String,
    val accessToken: String,
    val dtableUuid: String,
    val dtableServer: String,
    val workspaceID: Int?,
    val gateway: Boolean = false,
)

data class TSColumn(val key: String, val name: String, val type: String)
data class TSTable(val id: String?, val name: String, val columns: List<TSColumn>)
data class TSMetadata(val tables: List<TSTable>)

private val Context.tsStore by preferencesDataStore(name = "ts_config")
private val KEY_API_BASE  = stringPreferencesKey("apiBase")
private val KEY_API_TOKEN = stringPreferencesKey("apiToken")
private val KEY_ENCRYPTED_TOKEN = stringPreferencesKey("encryptedToken")

class TSClient internal constructor(
    private val store: DataStore<Preferences>,
    private val cipher: CredentialCipher,
    private val http: OkHttpClient = apiTransport(),
) {
    constructor(context: Context) : this(context.tsStore, CredentialCipher.android(context.packageName + ".credentials.v1"))

    @Volatile private var cached: TSAccess? = null
    @Volatile private var generation = 0L
    private val tokenLock = Mutex()

    val configFlow: Flow<TSConfig?> = store.data.map { p ->
        val base = p[KEY_API_BASE].orEmpty()
        val tok = (p[KEY_ENCRYPTED_TOKEN] ?: p[KEY_API_TOKEN]).orEmpty()
        if (base.isNotEmpty() && tok.isNotEmpty()) TSConfig(base, true, tok.hashCode()) else null
    }

    suspend fun configure(apiBase: String, apiToken: String): TSAccess = tokenLock.withLock {
        val base = serverBase(apiBase)
        require(apiToken.isNotBlank()) { "Enter a base API token" }
        val access = exchange(base, apiToken)
        store.edit { p ->
            p[KEY_API_BASE] = base
            p[KEY_ENCRYPTED_TOKEN] = cipher.encrypt(apiToken, base)
            p.remove(KEY_API_TOKEN)
        }
        generation++
        cached = access
        access
    }

    suspend fun disconnect() = tokenLock.withLock {
        store.edit { it.clear() }
        generation++
        cached = null
    }

    suspend fun ensureBaseToken(forceRefresh: Boolean = false): TSAccess = tokenLock.withLock {
        if (!forceRefresh) cached?.let { return@withLock it }
        val (base, token) = creds()
        exchange(serverBase(base), token).also { cached = it }
    }

    private suspend fun exchange(base: String, token: String): TSAccess {
        val obj = httpGetJSON("$base/api/v2.1/dtable/app-access-token/", "Bearer $token")
        try {
            val server = serverBase(obj.getString("dtable_server"))
            val uuid = obj.getString("dtable_uuid")
            require(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}").matches(uuid)) { "Invalid base UUID" }
            val access = obj.getString("access_token").also { require(it.isNotBlank()) { "Empty base token" } }
            return TSAccess(obj.optString("app_name"), access, uuid, server,
                if (obj.isNull("workspace_id")) null else obj.getInt("workspace_id"),
                obj.optBoolean("use_api_gateway", false) || java.net.URI(server).path.trimEnd('/').endsWith("/api-gateway"))
        } catch (e: Exception) { throw TSError.Decoding(e.message ?: "Invalid token response") }
    }

    private suspend fun baseGet(resource: String, query: String = ""): JSONObject {
        val expected = generation
        var access = ensureBaseToken()
        repeat(2) { attempt ->
            if (generation != expected) throw CancellationException("Account changed")
            val version = if (access.gateway) "v2" else "v1"
            try {
                val result = httpGetJSON("${access.dtableServer}/api/$version/dtables/${access.dtableUuid}/$resource/$query", "Bearer ${access.accessToken}")
                if (generation != expected) throw CancellationException("Account changed")
                return result
            } catch (e: TSError.Http) {
                if (attempt == 0 && e.status in listOf(401, 403)) {
                    if (generation != expected) throw CancellationException("Account changed")
                    access = ensureBaseToken(forceRefresh = true)
                } else throw e
            }
        }
        error("Unreachable retry state")
    }

    suspend fun metadata(): TSMetadata {
        val obj = baseGet("metadata")
        try {
        val payload = obj.optJSONObject("metadata") ?: obj
        val tablesArr = payload.getJSONArray("tables")
        val tables = (0 until tablesArr.length()).map { i ->
            val t = tablesArr.getJSONObject(i)
            val colsArr = t.getJSONArray("columns")
            val cols = (0 until colsArr.length()).map { j ->
                val c = colsArr.getJSONObject(j)
                TSColumn(
                    key = c.getString("key"),
                    name = c.getString("name"),
                    type = c.getString("type"),
                )
            }
            TSTable(id = t.optString("_id").ifBlank { null },
                    name = t.getString("name"),
                    columns = cols)
        }
        require(tables.map { it.name }.distinct().size == tables.size) { "Duplicate table names" }
        return TSMetadata(tables = tables)
        } catch (e: Exception) { throw TSError.Decoding(e.message ?: "Invalid metadata") }
    }

    suspend fun rows(table: String, limit: Int = 100): List<JSONObject> {
        require(table.isNotBlank() && limit in 1..1000) { "Select a table and a row limit from 1 to 1000" }
        val obj = baseGet("rows", "?table_name=${java.net.URLEncoder.encode(table, "UTF-8")}&limit=$limit")
        try {
            val rows = obj.getJSONArray("rows")
            return (0 until rows.length()).map { rows.getJSONObject(it) }
        } catch (e: Exception) { throw TSError.Decoding(e.message ?: "Invalid rows") }
    }

    private suspend fun httpGetJSON(url: String, auth: String): JSONObject {
        val request = Request.Builder().url(url).header("Authorization", auth).header("Accept", "application/json").build()
        try { return http.json(request) }
        catch (e: CancellationException) { throw e }
        catch (e: HttpFailure) { throw TSError.Http(e.status, null) }
        catch (e: ResponseFailure) { throw TSError.Decoding(e.message ?: "Invalid response") }
        catch (e: Exception) { throw TSError.Transport(e.message ?: "Request failed") }
    }

    private suspend fun creds(): Pair<String, String> {
        var tok = ""
        val p = store.edit { prefs ->
            tok = cipher.readAndMigrate(prefs, KEY_API_TOKEN, KEY_ENCRYPTED_TOKEN, prefs[KEY_API_BASE].orEmpty())
        }
        val base = p[KEY_API_BASE].orEmpty()
        if (base.isEmpty() || tok.isEmpty()) throw TSError.NotConfigured
        return base to tok
    }
}
