# Platform roadmap

Établi Table · state as of 2026-11-08 · this is a plan. Observed results stay in the
[current status page](current-status.qmd) and the [refinement record](refinement-2026-10.md);
Android release steps are detailed in
[android/SUBMISSION.md](https://github.com/etabli-dev/etabli-table/blob/main/android/SUBMISSION.md).

The [2026-11-08 Apple refinement](apple-audit-2026-11-08.md) records the implemented iOS metadata/detail parity and current unsigned build verification. Live-service and signed-distribution gates remain open.

## 1. Platform role

Établi Table is a **mobile-only** app for Android and iOS, on phones and tablets (the iOS
target already includes iPad). It is for looking up rows of a SeaTable base away from the
desk: pick a table, find a row, read its values.

No Ubuntu/Debian, Windows or macOS application is planned. SeaTable's own web interface is a
complete desktop client (views, forms, editing, automations) that a read-only browser cannot
match, so a desktop build would add maintenance without adding capability.

| Platform | Role | Used for |
|---|---|---|
| Android | release target | phones and tablets; signed APK on GitHub Releases, Google Play, later F-Droid |
| iOS / iPadOS | release target | iPhone and iPad; TestFlight, then App Store |
| Ubuntu/Debian, Windows, macOS | not planned | the SeaTable web interface in a browser |

## 2. Current state

| Platform | Status | Technology | How it is built | What is verified | Distribution |
|---|---|---|---|---|---|
| Android | in development | Kotlin 1.9.24, Jetpack Compose (Material 3), OkHttp 4.12, DataStore, Android Keystore; minSdk 26, compile/target SDK 36; AGP 8.13.2, Gradle 8.13, JDK 17 | `cd android && ./gradlew testDebugUnitTest lintDebug assembleDebug bundleRelease`; CI job `android` in `.github/workflows/android.yml` (ubuntu-24.04) | CI on 2026-10-31: unit and TLS-fixture tests (including base-token refresh and gateway v2/legacy v1 roots), lint, debug APK, unsigned release AAB. Locally: production-Keystore instrumented tests on an API 36 emulator (2026-10-31) and an account-free UI journey on an API 35 emulator (2026-11-02). Not verified: a live SeaTable server, a physical device, a release-signed build | GitHub Releases `v0.1.0` (2026-06-24): one APK signed with the Android debug key, built before the October–November changes. No Google Play or F-Droid listing |
| iOS | in development | SwiftUI, URLSession, Keychain; iOS 17+; iPhone and iPad | Xcode project `ios/EtabliTable.xcodeproj`; CI job `ios` (macos-15): `python3 scripts/check_swift.py` plus an unsigned simulator build | CI on 2026-10-31: Foundation client checks and the full unsigned simulator build. Not verified: any device run, a live server, signing | none (no TestFlight, no App Store) |
| Ubuntu/Debian | not planned | — | — | — | — |
| Windows | not planned | — | — | — | — |
| macOS | not planned | — | — | — | — (see decision D8 on iPad apps on Apple silicon Macs) |

Shared behaviour on both platforms: one base per account via a base API token; the short-lived
base token is refreshed once on 401/403; HTTPS only, authenticated redirects refused, 8 MiB
JSON bound, 45-second request budget; read-only UI (no row editing, no multi-base selector);
no pagination beyond the row limit.

## 3. Architecture

**Now.** Two independent native codebases with no shared code:

- `android/`: `net/TSClient.kt` (SeaTable client, base-token exchange and refresh, DataStore
  settings, Keystore-encrypted token), `net/HttpTransport.kt` (bounded, cancellable OkHttp),
  `ui/screens/BaseScreen.kt` (tables and rows) and `SettingsScreen.kt`.
- `ios/`: `App/Net/Client.swift` (`TSClient`), `App/Net/HttpTransport.swift`,
  `App/Shell/TablesView.swift` (table list, row grid in a sheet) and `SettingsView.swift`.
  `Client.swift` also contains `appendRows(table:rows:)`, which no screen uses.

What the two share today is the SeaTable contract (`/api/v2.1/dtable/app-access-token/`, then
`metadata` and `rows` under the returned dtable server for gateway v2 or legacy v1 roots), the
limits above and the Coder design tokens copied by `tool/sync_style.sh`.

**Target.** Keep two native apps; iOS stays SwiftUI. With no desktop target there is no reason
for a Kotlin Multiplatform module, and each client is a few hundred lines. Keep the platforms
in step with:

1. the parity tables in section 4, updated in the same commit as any feature change;
2. one set of HTTP reply fixtures (access token, metadata, rows for v1 and v2 roots, 401/403
   refresh) in a new top-level `fixtures/seatable/` folder, read by both
   `android/app/src/test/.../TSClientTest.kt` and `scripts/check_client.swift`;
3. the acceptance column of each parity row as the behaviour specification.

Writes (`appendRows` on iOS) stay out of both user interfaces until a write feature is planned
for both platforms together (decision D6).

## 4. Per-platform execution

### 4.1 Android

**Feature gap: present on iOS, missing on Android**

| # | Feature | Where it exists (iOS) | Android work | Accepted when |
|---|---|---|---|---|
| A1 | Row limit 500 | `ios/App/Net/Client.swift` `rows(table:limit: 500)` | `TSClient.rows` defaults to 100 and `BaseScreen.kt` says "first 100"; use the limit chosen in decision D7 on both platforms | Fixture test asserts `limit`; a reply above the 8 MiB bound fails visibly instead of truncating |
| A2 | Local text filter across all columns | `ios/App/Shell/TablesView.swift` (`filteredRows`, "filter rows (any column)") | Add a filter field above the rows that matches the displayed text of every column, case-insensitively, without a new request | Unit test for the matcher (numbers, booleans, lists, null); filtering 500 rows stays responsive on a mid-range device |
| A3 | Grid view with type-aware column widths and checkbox rendering | `TablesView.swift` `gridView`, `cell(row:column:)`, `columnWidth(for:)` | Today each row is a stack of `column: value` lines. Add a horizontally scrollable grid (one shared horizontal scroll state, fixed widths per column type, checkbox glyphs) and keep complete values reachable by tapping a row (see I1) | Headers stay aligned with cells while scrolling; TalkBack reads "column, value" per cell |
| A4 | Pull to refresh | `.refreshable` on the table list and rows | Replace the "Reload" button with Material 3 pull-to-refresh (keep an accessible refresh action) | Works with TalkBack |
| A5 | Theme choice Auto / Light / Dark | `ios/App/Shell/SettingsView.swift` (`ThemePreference`) | Store the choice in DataStore and pass it to `CoderTheme(darkOverride = …)`, which already accepts an override; Établi Focus has an Android implementation to mirror (`android/app/src/main/java/com/raban/etabli/focus/prefs/ThemePreference.kt`) | Choice survives relaunch; "Auto" follows the system |

**Build and run**

```sh
cd android
./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug bundleRelease
adb install -r app/build/outputs/apk/debug/app-debug.apk
./gradlew connectedDebugAndroidTest        # emulator or test device attached
```

Release candidate, once `android/keystore.properties` exists (see SUBMISSION.md):

```sh
./gradlew --no-daemon testDebugUnitTest lintRelease assembleRelease bundleRelease
"$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --print-certs app/build/outputs/apk/release/app-release.apk
"$ANDROID_HOME/build-tools/35.0.0/zipalign" -c -P 16 -v 4 app/build/outputs/apk/release/app-release.apk
```

**Packages and channels**

- *GitHub Releases:* release-signed APK plus `SHA256SUMS`; the hash in the release notes
  must equal GitHub's asset digest. A release-signed APK cannot update the debug-signed
  `v0.1.0` install: the release notes must say to uninstall it first (the token is excluded
  from backup, so users simply reconnect).
- *Google Play:* AAB (`bundleRelease`) with Play App Signing; internal testing, then closed
  testing, then production. The first upload of a new app is done in Play Console; later
  uploads can be automated.
- *F-Droid:* later (M8). Only listing text exists (`fastlane/metadata/android/en-US`); there
  is no build recipe yet. The dependencies (AndroidX, Compose, OkHttp) are free software, so
  a source build is realistic. With reproducible builds F-Droid can publish the developer
  signature, keeping GitHub, Play and F-Droid installs interchangeable (decision D1).

**Signing prerequisites (owner):** an app signing key and an upload key per decision D1,
kept outside the repository with backups; a Google Play developer account (D4); a privacy
policy URL (D5). CI secrets in a GitHub environment named `release` with the owner as
required reviewer: `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`; later `PLAY_SERVICE_ACCOUNT_JSON` for automated Play uploads.

**CI**

- Keep `android.yml` unchanged as the per-push verification.
- Add `.github/workflows/android-release.yml`: triggered by tags `v*` and
  `workflow_dispatch`; one job on ubuntu-24.04 in environment `release`; workflow-level
  `permissions: contents: read`, `contents: write` only on the job that creates the draft
  release; reuse the pinned `actions/checkout`, `actions/setup-java` and
  `android-actions/setup-android` SHAs from `android.yml`. Steps: decode the keystore into
  `$RUNNER_TEMP`, write `android/keystore.properties` with an absolute `storeFile`, run tests,
  `lintRelease assembleRelease bundleRelease`, verify the signature (fail if the certificate
  is `CN=Android Debug`) and 16 KB alignment, write `SHA256SUMS`, then
  `gh release create "$GITHUB_REF_NAME" --draft` with the APK and `SHA256SUMS`; keep the AAB
  as a workflow artifact for Play. Delete the keystore files in an `if: always()` step.
- Later: an internal-track Play upload step through the Play Developer API, pinned to a full
  commit SHA like every other action.

**Acceptance criteria (Android)**

- A1–A5 done, each with the automated test named in its row, green in CI.
- Live journey on a disposable SeaTable test base (D3), on a gateway v2 server and, if still
  reachable, a legacy v1 root: connect, list tables, open a wide table and a long table, filter
  rows, open a row's complete values, wait for or force a base-token expiry and see the single
  refresh succeed, disconnect.
- Release APK: `apksigner` shows the owner's certificate; the 16 KB alignment check passes;
  installs and runs on API 26 and API 36; an upgrade from the previous signed build keeps the
  account.
- Play: the internal-track build installs from the Play Store; the pre-launch report shows no
  crash; the Data safety answers match the shipped artifact.

### 4.2 iOS

**Feature gap: present on Android, missing on iOS**

| # | Feature | Where it exists (Android) | iOS work | Accepted when |
|---|---|---|---|---|
| I1 | Complete cell values | `BaseScreen.kt` prints every column value in full | `TablesView.swift` cells use `lineLimit(2)`; add a row-detail sheet listing every column with its complete, selectable value (and use the same detail on Android, see A3) | Long text and lists are readable in full on iPhone and iPad |
| I2 | Column names with their types | `BaseScreen.kt` "columns" card (`name·type`) | The table list shows only a column count; show names and types on the row sheet header or in a disclosure | Same information on both platforms |

**Build and run** (a Mac with Xcode; CI uses the default Xcode of macos-15):

```sh
python3 scripts/check_swift.py
xcodebuild -project ios/EtabliTable.xcodeproj -scheme EtabliTable -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Archive and upload to App Store Connect (TestFlight):

```sh
xcodebuild archive -project ios/EtabliTable.xcodeproj -scheme EtabliTable -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/EtabliTable.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
xcodebuild -exportArchive -archivePath build/EtabliTable.xcarchive -exportPath build/export \
  -exportOptionsPlist "$RUNNER_TEMP/export.plist" -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

`export.plist` sets `method` = `app-store-connect`, `destination` = `upload` and `teamID`. Write
it at run time: the repository's `.gitignore` excludes `ExportOptions.plist`.

**Distribution path:** TestFlight internal testing (no review) → external TestFlight (Beta
App Review) → App Store. Already in place: App icon, privacy manifest
(`ios/App/PrivacyInfo.xcprivacy`, declaring the UserDefaults and file-timestamp reasons),
`ITSAppUsesNonExemptEncryption = NO` in both build configurations. Still needed: iPhone and
iPad screenshots (the target includes iPad), privacy policy and support URLs, App Privacy
answers, age rating, and review notes with a reachable demo SeaTable base and its API token
(D3).

**Signing prerequisites (owner):** Apple Developer Program membership and Team ID (D4); the
bundle ID `com.raban.etabli.table` registered with an App Store Connect app record; an App
Store Connect API team key (Key ID, Issuer ID, `.p8`) whose role may manage signing (Admin, or
App Manager with access to certificates and profiles). If the key cannot manage cloud signing,
also an Apple Distribution certificate exported as `.p12`. CI secrets in environment `release`:
`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_B64`, and if needed
`IOS_DIST_CERT_P12_B64`, `IOS_DIST_CERT_PASSWORD`.

**CI**

- Keep the `ios` job in `android.yml` as the per-push check.
- Add `.github/workflows/ios-release.yml` (macos-15, tags `v*` and `workflow_dispatch`,
  environment `release`, `permissions: contents: read`): decode the API key into
  `$RUNNER_TEMP`, import the certificate into a temporary keychain if one is used, run
  `scripts/check_swift.py`, archive, export and upload as above; delete key and keychain in an
  `if: always()` step.

**Acceptance criteria (iOS)**

- I1–I2 done; `scripts/check_swift.py` and the simulator build green in CI.
- On an iPhone and an iPad (TestFlight build) against the test base: the same journey as
  Android; account kept after relaunch.
- VoiceOver reads grid cells and the row-detail sheet; the largest Dynamic Type size stays
  usable; iPad rotation and Split View keep the grid usable.
- The TestFlight build is processed and installs from the TestFlight app; App Review approves
  the submission.

### 4.3 Ubuntu/Debian — not planned

No Linux application is planned. SeaTable's web interface works in any desktop browser and
covers browsing plus everything this app does not (editing, views, forms); a native client
would duplicate a subset of it. On Ubuntu or Debian, open your SeaTable address in Firefox or
Chromium and keep it as a bookmark or browser shortcut.

### 4.4 Windows — not planned

No Windows application is planned, for the same reason: the SeaTable web interface in Edge,
Firefox or Chrome is the desktop client.

### 4.5 macOS — not planned

No macOS application is planned; use the SeaTable web interface in Safari or another browser.
Note that App Store Connect offers iPhone and iPad apps on Apple silicon Macs by default;
decision D8 covers whether to opt out until that is tested.

## 5. Milestones

Owner prerequisites (section 6) can be prepared in parallel with M1–M2.

1. **M1 — Android parity.** Implement A1, A4, A5, A2, A3 in that order (the grid last, with
   the row detail from I1). *Exit:* every A row marked done in this file with its test;
   `android.yml` green; account-free emulator journey repeated.
2. **M2 — iOS parity and shared fixtures.** I1–I2; move reply fixtures to `fixtures/seatable/`
   and read them from both test suites. *Exit:* both suites use the shared fixtures;
   `check_swift.py` and the simulator build green in CI.
3. **M3 — Android live acceptance.** Needs D3. *Exit:* the Android journey in 4.1 passes on an
   emulator and one physical device; results recorded in `docs/current-status.qmd`.
4. **M4 — Signed Android build on GitHub Releases.** Needs D1, D2. Add `android-release.yml`.
   *Exit:* a draft release with a release-signed APK and `SHA256SUMS`; signature, 16 KB alignment
   and upgrade path checked; README availability updated.
5. **M5 — Google Play.** Needs D4, D5. *Exit:* internal track installed; closed testing done
   (if the account requires it); production release approved.
6. **M6 — TestFlight.** Needs D4. Add `ios-release.yml`. *Exit:* a processed TestFlight build
   installed on an iPhone and an iPad; the iOS journey in 4.2 passes.
7. **M7 — App Store.** *Exit:* listing complete, App Review approved, release published.
8. **M8 — F-Droid (optional).** Needs D9. *Exit:* fdroiddata merge request with a source-build
   recipe accepted, or the decision not to publish recorded here.

At each exit, update the README availability lines and `docs/current-status.qmd` with what
was actually observed.

## 6. Owner decisions and prerequisites

| ID | Decision or prerequisite | Recommendation |
|---|---|---|
| D1 | Android signing model: own app signing key uploaded to Play App Signing plus a separate upload key, or a Google-generated app signing key | Own app signing key: GitHub, Play and reproducible F-Droid builds then share one signature and users can switch channels |
| D2 | Version scheme | Tag `vX.Y.Z` sets `versionName` and `MARKETING_VERSION`; a monotonically increasing integer sets `versionCode` and `CURRENT_PROJECT_VERSION`; first signed release above `0.1.0` |
| D3 | Disposable SeaTable test base with an API token reachable from the internet (cloud or self-hosted) | Required for live acceptance, Play "App access" and App Review; never a base with real data |
| D4 | Store accounts: Google Play developer account (personal or organisation) and Apple Developer Program (individual or organisation) | Check Play's rule for new personal accounts (currently a closed test with 12 opted-in testers for 14 days before production) |
| D5 | Privacy policy and support URLs | Host them on the documentation site; both stores require a privacy policy |
| D6 | Row writes on mobile (`appendRows` exists only in the iOS client, unused) | Keep the app read-only until both platforms reach parity and pass live acceptance; then add writes to both together or remove the unused iOS method |
| D7 | Row limit on both platforms (100 or 500; both clients accept 1–1000) | 500 with the local filter, provided the 8 MiB reply bound holds for typical wide tables; otherwise add paging |
| D8 | Offer the iPad app on Apple silicon Macs | Opt out in App Store Connect until it has been tested, consistent with macOS being "not planned" |
| D9 | F-Droid main repository with reproducible builds, or no F-Droid | Decide after M5 |
| D10 | Where CI signing secrets live: per-repository environment or organisation secrets for the suite | Per-repository `release` environment with required reviewer |
