// Copyright 2026 Raban Heller
// SPDX-License-Identifier: Apache-2.0

package com.raban.etabli.table.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import com.raban.etabli.table.EtabliTableApplication
import com.raban.etabli.table.ui.screens.BaseScreen
import com.raban.etabli.table.ui.screens.SettingsScreen
import com.raban.etabli.table.ui.theme.Coder

@Composable
fun RootScreen(app: EtabliTableApplication) {
    val t = Coder.tokens
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Scaffold(
        containerColor = t.color.paper,
        bottomBar = {
            NavigationBar(containerColor = t.color.surface) {
                listOf(
                    Triple("Base",     Icons.Default.TableChart, 0),
                    Triple("Settings", Icons.Default.Settings,   1),
                ).forEach { (label, icon, idx) ->
                    NavigationBarItem(
                        selected = tab == idx,
                        onClick = { tab = idx },
                        icon = { Icon(icon, contentDescription = label) },
                        label = { Text(label, style = t.font.mono) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = t.color.accent,
                            selectedTextColor = t.color.accent,
                            indicatorColor = t.color.accentMuted,
                            unselectedIconColor = t.color.faint,
                            unselectedTextColor = t.color.faint,
                        ),
                    )
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding).background(t.color.paper)) {
            when (tab) {
                0 -> BaseScreen(app)
                else -> SettingsScreen(app)
            }
        }
    }
}
