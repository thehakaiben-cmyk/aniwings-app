# Desktop cleanup and run configuration — 6 October 2026

Update: an Android emulator preview target has since been restored at the user’s
request. Select **AniWings Desktop (Emulator Preview)** for Android, or **AniWings
Desktop (Windows)** for the native app. The older cleanup record below describes
the previous desktop-only configuration; see README for current preview instructions.

The supplied log ran `lib/main.dart` on `emulator-5554` and loaded the old TV
pairing define file. Its fatal error was in the Android torrent plugin: GitHub
binary downloads timed out, then the source fallback could not find
`openssl/err.h`. This was an Android build of a desktop project.

## Changes

- Archived the Android target and unsupported macOS template, old APKs, scratch
  scripts, failure images, stale IDE Android configuration and generated caches.
- Archived the copied shared Firestore deployment rules; this desktop checkout no
  longer deploys website/TV security policy. No deployed Firestore rules were changed.
- Removed TV QR pairing screens/services/tests/configuration, voice/ambient TV
  modules and their unused preference code. Desktop email/password authentication
  and Cloudflare desktop account metadata synchronization remain connected.
- Replaced `Tv*` aliases and imports with the actual `Desktop*` classes, including
  layout, keyboard focus, navigation, sidebar, settings and device gate.
- Removed unused Browse/Schedule duplicate screens, old splash wrapper, glass/button
  helpers, web iframe adapters and the mock Google account selector.
- Removed direct Android video/WebView/Google Sign-In pins, Google Fonts, QR
  dependencies and browser-only dependencies. Platform implementations that Flutter
  packages bring transitively are dependency metadata, not app targets.
- Replaced the incompatible mobile WebView path with the existing Windows WebView2
  package while retaining embedded-player controls and extraction callbacks.
  Initialization finishes before channel setup/navigation, and native views dispose
  when the player leaves the screen. Native media headers remain on the native
  player; this Windows WebView package does not expose custom document headers.
- External AniList/MAL authorization uses the system browser and existing callback
  handling. Unused TV token authentication and Android Google Sign-In code were
  removed. The retained Google service path uses Firebase's Windows provider API.
- Update URLs resolve desktop installers instead of falling back to TV APKs.
- Corrected Home header sizing using available content width, wrapped hero metadata,
  and constrained the Settings title to prevent overflow.

## Run the desktop app

Android Studio: select **AniWings Desktop (Windows)** and reload the project if the
IDE still shows its old configuration. The saved configuration passes
`--device-id=windows`; this was verified to select Windows even when an old emulator
argument is supplied earlier. The old Android module and pairing define are gone.

```powershell
flutter pub get
flutter run -d windows
# Or:
./tool/run-desktop.ps1
```

The original Android/OpenSSL failure is no longer part of this project's build.
A native Windows build currently stops at **Unable to find suitable Visual Studio
toolchain**. Install Visual Studio 2022 with **Desktop development with C++**, MSVC,
the Windows SDK and CMake. Dependency installation/plugin symlink generation now
succeeds on this machine. No Windows executable has been produced or verified yet.

Linux remains a native video/torrent target, but Firebase login is not configured
for Linux and embedded WebView2/window integration is Windows-only.

## Recovery

Source/configuration backup before cleanup:
`C:/Users/senth/.codex/backups/aniwings-desktop-before-cleanup-20261006-095852.zip`.
Archived removals: `C:/Users/senth/.codex/backups/aniwings-desktop-removed-20261006`.
Archived old build caches: `C:/Users/senth/.codex/backups/aniwings-desktop-generated-20261006`.
These archives are outside the app project and are not compiled or analyzed.

## Validation

Run `flutter analyze` and `flutter test`. The remaining suites cover desktop
navigation/authentication, provider preferences, settings, Home-to-Settings routing,
connectivity, player geometry/skipping, torrent rules, login persistence, catalog
identity and Windows WebView initialization/disposal/failure handling. Tests mock
catalog/update requests instead of assuming that a real network is available.

Final verification: 128 tests passed; the unused skipped preview test was removed and the remaining auth tests passed again. Flutter analysis reports no issues. The import graph has no unreachable production Dart files. The removed packages are absent from the resolved dependency graph.
