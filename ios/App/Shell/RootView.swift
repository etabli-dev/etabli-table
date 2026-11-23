// Copyright 2026 R. Heller
// SPDX-License-Identifier: AGPL-3.0-only

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
