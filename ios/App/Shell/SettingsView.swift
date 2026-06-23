import SwiftUI

struct SettingsView: View {
    @Environment(TSClient.self) private var client
    @AppStorage(ThemePreference.userDefaultsKey) private var themeRaw: String = ThemePreference.system.rawValue
    private var theme: ThemePreference { ThemePreference(rawValue: themeRaw) ?? .system }

    @State private var urlText = ""
    @State private var token = ""
    @State private var connecting = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        ZStack {
            Theme.Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    PromptHeader(["settings"])
                    Text("Connection")
                        .font(Theme.Font.display).foregroundStyle(Theme.Color.ink)
                    if let cfg = client.config { connectedCard(cfg) } else { connectCard }
                    Card(title: "appearance", systemImage: "paintbrush") {
                        Picker("Theme", selection: Binding(
                            get: { theme }, set: { themeRaw = $0.rawValue }
                        )) {
                            ForEach(ThemePreference.allCases) { p in
                                Label(p.label, systemImage: p.systemImage).tag(p)
                            }
                        }.pickerStyle(.segmented)
                    }
                    Card(title: "about", systemImage: "info.circle") {
                        Text("EtabliTable").font(Theme.Font.headline).foregroundStyle(Theme.Color.ink)
                        Text("SeaTable companion — browse/search rows of a base. Uses SeaTable's API-Token + short-lived Base-Token flow with auto-refresh.")
                            .font(Theme.Font.body).foregroundStyle(Theme.Color.faint)
                    }
                }.padding(Theme.Space.lg)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var connectCard: some View {
        Card(title: "configure", systemImage: "link") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Generate a base API token in SeaTable: Base → Advanced → API Tokens → New. Paste it below — EtabliTable exchanges it for a short-lived Base-Token on each session and stores only the long-lived token in the iOS Keychain.")
                    .font(Theme.Font.body).foregroundStyle(Theme.Color.ink)
                field("server URL", text: $urlText, placeholder: "https://cloud.seatable.io")
                field("base API token", text: $token, placeholder: "paste token", secure: true)
                if let info { StatusLabel(info, tone: .accent) }
                if let error {
                    Text(error).font(Theme.Font.body).foregroundStyle(Theme.Color.danger)
                }
                PrimaryButton(connecting ? "Verifying…" : "Configure",
                              systemImage: "checkmark.seal",
                              enabled: !urlText.isEmpty && !token.isEmpty && !connecting) {
                    configure()
                }
            }
        }
    }

    private func connectedCard(_ cfg: TSConfig) -> some View {
        Card(title: "configured", systemImage: "checkmark.circle") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                MonoLabel(cfg.apiBase.absoluteString)
                if let base = client.activeBase {
                    StatusLabel("base: \(base.app_name ?? base.dtable_uuid)", tone: .accent)
                }
                Button(role: .destructive) {
                    try? client.disconnect()
                } label: {
                    Text("Disconnect").font(Theme.Font.body.weight(.semibold))
                        .padding(.horizontal, Theme.Space.md).padding(.vertical, Theme.Space.sm)
                        .foregroundStyle(Theme.Color.surface)
                        .background(Theme.Color.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            MonoLabel(label, color: Theme.Color.faint)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else      { TextField(placeholder, text: text) }
            }
            .textFieldStyle(.plain)
            .font(Theme.Font.monoBody).foregroundStyle(Theme.Color.ink)
            .padding(Theme.Space.sm).background(Theme.Color.paper)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(Theme.Color.hairline, lineWidth: 1))
            .autocorrectionDisabled().textInputAutocapitalization(.never)
        }
    }

    private func configure() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else {
            error = "Invalid URL"; return
        }
        connecting = true; error = nil; info = nil
        Task {
            do {
                try client.configure(apiBase: url, apiToken: token.trimmingCharacters(in: .whitespaces))
                let active = try await client.ensureBaseToken(forceRefresh: true)
                info = "Connected to base: \(active.app_name ?? active.dtable_uuid)"
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            connecting = false
        }
    }
}
