# AniWings Desktop

This checkout targets native Windows and Linux desktops. An Android debug target
is also available to preview the same desktop interface in an emulator. TV pairing
and TV compatibility aliases remain removed.

## Windows development

Install Visual Studio 2022 with **Desktop development with C++**, including the
Windows SDK and CMake. Enable Windows Developer Mode for Flutter plugin symlinks.

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows

# Release build:
./tool/build-release.ps1
```

Release builds are placed in `./release/`:
- Windows: `release/aniwings-desktop-windows-v<version>.exe` (e.g. `aniwings-desktop-windows-v1.2.5.exe`)
- Linux: `release/aniwings-desktop-linux-v<version>.AppImage` (e.g. `aniwings-desktop-linux-v1.2.5.AppImage`)

## Linux development & releases

To build the AppImage on Linux or in CI:
```bash
chmod +x ./tool/build-release.sh
./tool/build-release.sh
```

A GitHub Actions workflow is also configured in `.github/workflows/release.yml` to automatically build both Windows (`.exe`) and Linux (`.AppImage`) upon pushing a version tag (e.g., `v1.2.5`) or triggering manually.

The Windows runner starts at 1280 × 720, has a 1024 × 600 minimum size, and handles
native fullscreen, window restoration, and keeping the display awake during playback.

## Emulator preview

In Android Studio, choose **AniWings Desktop (Emulator Preview)** and your running
**Large Desktop** emulator. Windows has its own separate run configuration.

```powershell
flutter run -d emulator-5554 --dart-define=DESKTOP_EMULATOR_PREVIEW=true
```

Android debug runs enable preview mode by default. Preview uses the desktop UI in
landscape with Android video playback. Windows-only torrent streaming and WebView2
are unavailable in this preview. The local torrent package registers native code
only on Windows/Linux, so Android does not compile its OpenSSL/CMake sources.
Android release startup stays disabled unless preview is explicitly enabled.
See [preview setup and emulator DNS troubleshooting](docs/emulator-preview.md).

## Verification

```powershell
flutter analyze
flutter test
```

See [desktop changes](docs/desktop-fixes.md) and [cleanup and run configuration](docs/desktop-cleanup.md).

## Native dependencies

Windows/Linux video uses `video_player_media_kit` with the existing custom player.
Torrent streaming uses `libtorrent_flutter` (GPL-3.0) and its bundled native engine.
The first native build downloads the engine binaries. A desktop build is required
for native torrent execution; ordinary Flutter widget tests do not load those DLLs.
