// Copyright 2026 R. Heller
// SPDX-License-Identifier: Apache-2.0

package com.raban.etabli.table.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.raban.etabli.table.EtabliTableApplication
import com.raban.etabli.table.net.TSAccess
import com.raban.etabli.table.ui.theme.*
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(app: EtabliTableApplication) {
    val t = Coder.tokens
    val scope = rememberCoroutineScope()
    val current by app.client.configFlow.collectAsState(initial = null)
    var base by remember(current) { mutableStateOf(current?.apiBase ?: "https://cloud.seatable.io") }
    var token by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    var statusTone by remember { mutableStateOf(StatusTone.Info) }
    var access by remember { mutableStateOf<TSAccess?>(null) }
    var busy by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().background(t.color.paper)
            .verticalScroll(rememberScrollState()).padding(t.space.lg),
        verticalArrangement = Arrangement.spacedBy(t.space.lg),
    ) {
        PromptHeader(listOf("settings", "seatable"))

        Card(title = "server", icon = Icons.Default.Cloud) {
            MonoLabel("API base URL", color = t.color.faint)
            TextInput(value = base, placeholder = "https://cloud.seatable.io", onChange = { base = it })
        }
        Card(title = "API token", icon = Icons.Default.VpnKey) {
            MonoLabel("long-lived, generated per base in SeaTable UI", color = t.color.faint)
            TextInput(value = token, placeholder = "paste token…", onChange = { token = it }, isSecret = true)
        }
        Card(title = "session", icon = Icons.Default.Lock) {
            MonoLabel("a short-lived base token is exchanged on first call and refreshed on 401.",
                      color = t.color.faint)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(t.space.md)) {
            PrimaryButton(if (busy) "Connecting…" else "Save & test",
                          icon = Icons.Default.CheckCircle, enabled = !busy) {
                scope.launch {
                    busy = true; status = null; access = null
                    try {
                        app.client.configure(base.trim(), token.trim())
                        access = app.client.ensureBaseToken(forceRefresh = true)
                        status = "OK — base \"${access!!.appName}\" reachable."
                        statusTone = StatusTone.Accent
                        token = ""
                    } catch (e: Throwable) {
                        status = e.message ?: "Failed"
                        statusTone = StatusTone.Danger
                    } finally { busy = false }
                }
            }
            if (current != null) {
                PrimaryButton("Disconnect", icon = Icons.AutoMirrored.Filled.Logout) {
                    scope.launch {
                        app.client.disconnect()
                        status = "Disconnected"
                        statusTone = StatusTone.Info
                        access = null
                    }
                }
            }
        }
        status?.let { StatusLabel(it, tone = statusTone) }

        Card(title = "current") {
            if (current == null) {
                MonoLabel("not connected.", color = t.color.faint)
            } else {
                Row(horizontalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxWidth()) {
                    MonoLabel("server"); MonoLabel(current!!.apiBase, color = t.color.faint)
                }
                Row(horizontalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxWidth()) {
                    MonoLabel("api token"); MonoLabel("✓ stored", color = t.color.accent)
                }
                access?.let {
                    Row(horizontalArrangement = Arrangement.SpaceBetween,
                        modifier = Modifier.fillMaxWidth()) {
                        MonoLabel("base"); MonoLabel(it.appName, color = t.color.faint)
                    }
                    Row(horizontalArrangement = Arrangement.SpaceBetween,
                        modifier = Modifier.fillMaxWidth()) {
                        MonoLabel("dtable server"); MonoLabel(it.dtableServer, color = t.color.faint)
                    }
                }
            }
        }
    }
}
