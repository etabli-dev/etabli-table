// Copyright 2026 Raban Heller
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { TablesView() }
                .tabItem { Label("Base", systemImage: "tablecells") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
