// Copyright 2026 Raban Heller
// SPDX-License-Identifier: Apache-2.0

package com.raban.etabli.table

import android.app.Application
import com.raban.etabli.table.net.TSClient

class EtabliTableApplication : Application() {
    lateinit var client: TSClient
        private set

    override fun onCreate() {
        super.onCreate()
        client = TSClient(this)
    }
}
