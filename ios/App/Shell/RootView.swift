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
