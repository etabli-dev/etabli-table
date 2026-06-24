// Copyright 2026 R. Heller
// SPDX-License-Identifier: Apache-2.0

package com.raban.etabli.table.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.raban.etabli.table.EtabliTableApplication
import com.raban.etabli.table.net.TSMetadata
import com.raban.etabli.table.net.TSTable
import com.raban.etabli.table.ui.theme.*
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun BaseScreen(app: EtabliTableApplication) {
    val t = Coder.tokens
    val scope = rememberCoroutineScope()
    val config by app.client.configFlow.collectAsState(initial = null)
    var meta by remember { mutableStateOf<TSMetadata?>(null) }
    var selected by remember { mutableStateOf<TSTable?>(null) }
    var rows by remember { mutableStateOf<List<JSONObject>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }

    fun loadMetadata() {
        if (config == null) { meta = null; rows = null; return }
        scope.launch {
            loading = true; error = null
            try {
                meta = app.client.metadata()
                selected = meta?.tables?.firstOrNull()
                selected?.let { rows = app.client.rows(it.name, limit = 100) }
            } catch (e: Throwable) { error = e.message; meta = null }
            finally { loading = false }
        }
    }

    fun loadRows(tbl: TSTable) {
        scope.launch {
            loading = true; error = null
            selected = tbl
            try { rows = app.client.rows(tbl.name, limit = 100) }
            catch (e: Throwable) { error = e.message; rows = null }
            finally { loading = false }
        }
    }

    LaunchedEffect(config) { loadMetadata() }

    Column(
        modifier = Modifier.fillMaxSize().background(t.color.paper).padding(t.space.lg),
        verticalArrangement = Arrangement.spacedBy(t.space.md),
    ) {
        PromptHeader(listOf("base", selected?.name ?: "—"))

        when {
            config == null   -> Card(title = "not connected") {
                MonoLabel("set the server + API token in Settings first.", color = t.color.faint)
            }
            loading && meta == null -> LoadingState("loading metadata…")
            error != null && meta == null -> ErrorState("Couldn't load", detail = error, onRetry = ::loadMetadata)
            meta == null     -> Spacer(Modifier.size(0.dp))
            else -> {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(t.space.sm)) {
                    items(meta!!.tables, key = { it.name }) { tbl ->
                        TableChip(label = tbl.name, selected = selected?.name == tbl.name) { loadRows(tbl) }
                    }
                }
                selected?.let { tbl ->
                    Card(title = "columns", icon = Icons.Default.ViewColumn) {
                        Row(horizontalArrangement = Arrangement.spacedBy(t.space.xs),
                            modifier = Modifier.horizontalScroll(rememberScrollState())) {
                            tbl.columns.forEach { c ->
                                StatusLabel("${c.name}·${c.type}", tone = StatusTone.Info)
                            }
                        }
                    }
                    Card(title = "rows (${rows?.size ?: "—"})", icon = Icons.Default.TableChart) {
                        when {
                            loading -> MonoLabel("loading rows…", color = t.color.faint)
                            error != null -> MonoLabel("⚠ $error", color = t.color.danger)
                            rows == null -> MonoLabel("—", color = t.color.faint)
                            rows!!.isEmpty() -> MonoLabel("(empty)", color = t.color.faint)
                            else -> Column {
                                rows!!.take(50).forEachIndexed { idx, row ->
                                    if (idx > 0) Spacer(Modifier.height(t.space.xs))
                                    MonoLabel(row.toString().take(140), color = t.color.faint)
                                }
                            }
                        }
                    }
                }
            }
        }
        if (config != null) {
            PrimaryButton("Reload", icon = Icons.Default.Refresh, onClick = ::loadMetadata)
        }
    }
}

@Composable
private fun TableChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val t = Coder.tokens
    Box(
        modifier = Modifier
            .background(if (selected) t.color.accent.copy(alpha = 0.12f) else t.color.surface,
                        androidx.compose.foundation.shape.RoundedCornerShape(t.radius.sm))
            .clickable(onClick = onClick)
            .padding(horizontal = t.space.md, vertical = t.space.sm)
    ) {
        Text(label, style = t.font.caption.copy(
            color = if (selected) t.color.accent else t.color.faint
        ))
    }
}
