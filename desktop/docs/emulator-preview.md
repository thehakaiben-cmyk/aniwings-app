# Emulator preview — 6 October 2026

The desktop app can now be previewed on an Android emulator. Android preview mode
is enabled for debug runs, and the **AniWings Desktop (Emulator Preview)** run
configuration explicitly passes `DESKTOP_EMULATOR_PREVIEW=true`. The same desktop
layout/theme is used; the preview runs in landscape and hides Android system bars.
Email/password login uses the restored Android Firebase app configuration.

The previous `openssl/err.h` build failure came from compiling the torrent plugin
for Android. `third_party/libtorrent_flutter` retains the upstream 2.0.0 native
engine and license but registers it only on Windows/Linux. The generated Android
plugin list excludes that engine and the Windows WebView plugin. Android previews
use the compatible Android video backend. Native torrent streaming and embedded
WebView2 playback still require a desktop build; use native HLS servers in preview.

## Run

Select **AniWings Desktop (Emulator Preview)** in Android Studio, and select the
running **Large Desktop** AVD as the device. Reload the project if the new run
configuration has not appeared.

```powershell
flutter run -d emulator-5554 --dart-define=DESKTOP_EMULATOR_PREVIEW=true
# Or:
./tool/run-emulator-preview.ps1
```

The installed preview APK is `build/app/outputs/flutter-apk/app-debug.apk`.
The debug build and normal `flutter run` both completed successfully and the app
was installed/launched on `emulator-5554`. All 131 tests passed; analysis is clean.

## Emulator DNS

The initial emulator was offline. After restarting it, the Android guest still
could not resolve `www.cloudflare.com`, although an HTTP request to `1.1.1.1`
worked. Cold-booting with explicit DNS servers restored hostname resolution.
If this happens again, close the running AVD before starting it with:

```powershell
& "$env:LOCALAPPDATA/Android/sdk/emulator/emulator.exe" -avd Large_Desktop -no-snapshot-load -dns-server 1.1.1.1,8.8.8.8
```

This is an emulator networking setting. Host Windows DNS settings were not changed.
Release Android startup stays disabled unless preview mode is explicitly enabled.

Final device verification: the Large Desktop AVD resolved catalog hosts after the DNS cold boot. The guest was awakened/unlocked and its emulated AC power enabled. The desktop Home screen rendered with catalog artwork loaded; screenshot: build/aniwings-desktop-preview.png. The app remains running on emulator-5554.
