// Copyright 2026 R. Heller
// SPDX-License-Identifier: LicenseRef-Proprietary

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
