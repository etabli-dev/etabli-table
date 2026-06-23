// Copyright 2026 Raban Heller
// SPDX-License-Identifier: Apache-2.0

package com.raban.etabli.table

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.raban.etabli.table.ui.RootScreen
import com.raban.etabli.table.ui.theme.CoderTheme

class MainActivity : ComponentActivity() {
    private val app get() = application as EtabliTableApplication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { CoderTheme { RootScreen(app) } }
    }
}
