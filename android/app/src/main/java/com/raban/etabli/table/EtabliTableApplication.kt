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
