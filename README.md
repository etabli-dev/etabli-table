# Etabli Table

> Browse and edit your SeaTable bases.

`iOS` `Android` · Apache-2.0 · Part of the [Etabli Suite](https://github.com/etabli-dev)

Etabli Table is a client for a self-hosted SeaTable backend. Browse and edit tables and rows. Uses a two-token hierarchy (long-lived API token exchanged for a short-lived base token, cached and auto-refreshed). Talks only to your own server.

## Availability

- **App Store (iOS):** available.
- **Google Play:** available.
- **F-Droid (main repo):** built from this repo's `/android` source.

## Privacy

No analytics. No third-party SDKs. No accounts. Credentials, where needed, live only in the platform secure store (iOS Keychain / Android EncryptedSharedPreferences). This app talks only to the self-hosted server you point it at — never to any service operated by the author.

## Repository layout

```
ios/        SwiftUI app
android/    Kotlin + Jetpack Compose app
fastlane/   F-Droid / store listing metadata
```

Both platforms are one product, sharing the Coder Design System tokens.

## Tech

iOS: SwiftUI + URLSession. Android: Compose, OkHttp, DataStore

**Status:** Complete on both platforms

## Support development

- 💚 **[Liberapay](https://liberapay.com/rabanheller/)** — recurring, 0% commission, shown on F-Droid.
- ☕ [Buy Me a Coffee](https://buymeacoffee.com/rabanheller) — one-off tip (also the in-app link on iOS/Android).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Copyright 2026 Raban Heller.
