package com.raban.etabli.table.net

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
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
//   1. user-generated long-lived API token (per-base) → stored in DataStore
//   2. short-lived access_token + dtable_server + dtable_uuid obtained by
//      GET /api/v2.1/dtable/app-access-token/ with the API token.
//
// Refreshed lazily — if a base call returns 401 we wipe & retry once.

data class TSConfig(val apiBase: String, val hasToken: Boolean)

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
)

data class TSColumn(val key: String, val name: String, val type: String)
data class TSTable(val id: String?, val name: String, val columns: List<TSColumn>)
data class TSMetadata(val tables: List<TSTable>)

private val Context.tsStore by preferencesDataStore(name = "ts_config")
private val KEY_API_BASE  = stringPreferencesKey("apiBase")
private val KEY_API_TOKEN = stringPreferencesKey("apiToken")

class TSClient(private val context: Context) {
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .build()

    @Volatile private var cached: TSAccess? = null

    val configFlow: Flow<TSConfig?> = context.tsStore.data.map { p ->
        val base = p[KEY_API_BASE].orEmpty()
        val tok = p[KEY_API_TOKEN].orEmpty()
        if (base.isNotEmpty() && tok.isNotEmpty()) TSConfig(base, true) else null
    }

    suspend fun configure(apiBase: String, apiToken: String) {
        context.tsStore.edit { p ->
            p[KEY_API_BASE] = apiBase.trimEnd('/')
            p[KEY_API_TOKEN] = apiToken
        }
        cached = null
    }

    suspend fun disconnect() {
        context.tsStore.edit { it.clear() }
        cached = null
    }

    suspend fun ensureBaseToken(forceRefresh: Boolean = false): TSAccess {
        if (!forceRefresh) cached?.let { return it }
        val (base, token) = creds()
        val obj = httpGetJSON("$base/api/v2.1/dtable/app-access-token/", "Token $token")
        val a = TSAccess(
            appName = obj.optString("app_name"),
            accessToken = obj.getString("access_token"),
            dtableUuid = obj.getString("dtable_uuid"),
            dtableServer = obj.getString("dtable_server").trimEnd('/'),
            workspaceID = if (obj.has("workspace_id")) obj.optInt("workspace_id") else null,
        )
        cached = a
        return a
    }

    suspend fun metadata(): TSMetadata {
        val a = ensureBaseToken()
        val obj = httpGetJSON(
            "${a.dtableServer}/dtable-server/api/v1/dtables/${a.dtableUuid}/metadata/",
            "Token ${a.accessToken}",
        )
        val payload = obj.optJSONObject("metadata") ?: obj
        val tablesArr = payload.optJSONArray("tables") ?: JSONArray()
        val tables = (0 until tablesArr.length()).map { i ->
            val t = tablesArr.getJSONObject(i)
            val colsArr = t.optJSONArray("columns") ?: JSONArray()
            val cols = (0 until colsArr.length()).map { j ->
                val c = colsArr.getJSONObject(j)
                TSColumn(
                    key = c.optString("key"),
                    name = c.optString("name"),
                    type = c.optString("type"),
                )
            }
            TSTable(id = t.optString("_id").ifBlank { null },
                    name = t.optString("name"),
                    columns = cols)
        }
        return TSMetadata(tables = tables)
    }

    suspend fun rows(table: String, limit: Int = 100): List<JSONObject> {
        val a = ensureBaseToken()
        val obj = httpGetJSON(
            "${a.dtableServer}/dtable-server/api/v1/dtables/${a.dtableUuid}/rows/" +
                "?table_name=${java.net.URLEncoder.encode(table, "UTF-8")}&limit=$limit",
            "Token ${a.accessToken}",
        )
        val arr = obj.optJSONArray("rows") ?: JSONArray()
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    private suspend fun httpGetJSON(url: String, auth: String): JSONObject = withContext(Dispatchers.IO) {
        val req = Request.Builder().url(url)
            .header("Authorization", auth)
            .header("Accept", "application/json")
            .build()
        try {
            http.newCall(req).execute().use { resp ->
                val text = resp.body?.string().orEmpty()
                if (!resp.isSuccessful) throw TSError.Http(resp.code, text)
                try { JSONObject(text) }
                catch (t: Throwable) { throw TSError.Decoding(t.message ?: "?") }
            }
        } catch (e: TSError) { throw e } catch (t: Throwable) {
            throw TSError.Transport(t.message ?: "?")
        }
    }

    private suspend fun creds(): Pair<String, String> {
        val p = context.tsStore.data.first()
        val base = p[KEY_API_BASE].orEmpty()
        val tok = p[KEY_API_TOKEN].orEmpty()
        if (base.isEmpty() || tok.isEmpty()) throw TSError.NotConfigured
        return base to tok
    }
}
