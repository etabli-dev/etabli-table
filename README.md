# Établi Table

> SeaTable base and row browser.

`iOS` `Android` · Apache-2.0 · Part of the [Établi Suite](https://github.com/etabli-dev)

Both platforms browse the tables and rows in one configured SeaTable base. Android shows the first 100 rows with complete column values; iOS shows up to 500 with a local text filter. Row editing and a multi-base account selector are not exposed in the application UI. Further pagination is deferred.

## Availability

Établi Table is **under active development**. There are no App Store, Google Play or F-Droid releases yet.

- **Android:** install the current **development build** as a signed **APK** from **[GitHub Releases](../../releases)**.
- **App Store (iOS):** planned — not yet available.
- **Google Play:** planned — not yet available.
- **F-Droid:** planned — not yet available.

## First use

Create an API token for your base in SeaTable and enter it with the HTTPS server URL in Settings. Connect, choose a table, and inspect its rows. A short-lived base token is obtained automatically; a 401/403 refreshes it once and rebuilds the request from the new server URL. Current gateway v2 roots and returned legacy v1 roots are supported.

Use the canonical HTTPS URL: authenticated redirects are refused, and normal
system certificate validation remains enabled. Reconnect after restoring an
Android backup; the encrypted token file is deliberately excluded from backup.
A lost or unreadable key does not cause the app to overwrite the saved data.

JSON replies are limited to 8 MiB and requests have a 45-second total timeout.
Failures and cancellation remain visible or cancel the active operation; they
are not converted into empty successful lists.

## Build and checks

Android prerequisites: JDK 17, Android SDK 36 and build-tools 35.0.0,
with `ANDROID_HOME` pointing to that SDK.

```sh
cd android
./gradlew testDebugUnitTest lintDebug assembleDebug bundleRelease
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Open the app and follow the server setup above. The debug APK is for testing;
the release AAB is unsigned until a signing configuration is supplied. For iOS,
open `ios/EtabliTable.xcodeproj` in Xcode, choose your development team and an
iOS 17+ destination, then run.

The Foundation client checks run with macOS command-line tools and Python 3:

```sh
python3 scripts/check_swift.py
```

These checks compile the production client/transport/Keychain wrapper, exercise
the client using isolated in-memory credentials and HTTP protocol fixtures, and
parse the SwiftUI sources. They do not establish a complete iOS build or a real
server connection. Android TLS fixtures use normal trust validation with a local
test certificate. See [the refinement record](docs/refinement-2026-10.md).

With an attached Android emulator or test device, run the production Keystore
and credential-migration checks from `android/`:

```sh
./gradlew connectedDebugAndroidTest
```

These use isolated test keys and storage; they do not connect to your server.

## Privacy and storage

No analytics or author-operated service. You use your own server account;
requests go to that server, or the HTTPS base-server URL it returns.
Android uses Compose, OkHttp and DataStore; its token is protected by an
app-specific Android Keystore AES-256-GCM key and bound to the configured server.
Existing plaintext Android tokens migrate atomically on first use. iOS stores
the server/token pair in one Keychain item; existing installations retain legacy
read compatibility. Server addresses and UI settings are also local preferences.

Server content is loaded for viewing; no background synchronization service is implemented.

## Readiness and deferred work

Android crypto and server integration tests (8), lint, debug APK and release
bundle passed locally before the final screen review. Swift client checks and
production Foundation typechecking also passed. Final screen/build evidence is
recorded in the refinement record. Remote CI, a current SwiftUI/Xcode build,
device accessibility/lifecycle/credential restore and a real-server journey remain
separate acceptance gates. No store submission or deployment was performed.

Next release step: run the documented journey on both devices with a test server,
resolve device findings, configure signing and prepare the store package for approval.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
Copyright 2026 R. Heller.
