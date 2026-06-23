import SwiftUI

@main
struct EtabliTableApp: App {
    @AppStorage(ThemePreference.userDefaultsKey) private var themeRaw: String = ThemePreference.system.rawValue
    @State private var client = TSClient()
    private var theme: ThemePreference { ThemePreference(rawValue: themeRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
                .preferredColorScheme(theme.colorScheme)
                .tint(Theme.Color.accent)
        }
    }
}
