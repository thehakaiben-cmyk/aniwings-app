# AniWings Desktop — Workspace Rules & Instructions

## Release Build & Output Guidelines

Whenever building the application for release (or running build scripts), adhere strictly to the following rules:

1. **Release Destination Folder**:
   - All release outputs and binaries must be placed in the `release/` directory at the project root (`./release/`).
   - If the `release/` folder does not exist, create it automatically prior to copying/generating the release artifacts.

2. **Release Artifact Naming Convention**:
   The generated release files must follow this exact naming format:
   - **Windows**: `aniwings-desktop-windows-v<version>.exe`
     * Example: For version 1.2.5, name the file `aniwings-desktop-windows-v1.2.5.exe`
   - **Linux**: `aniwings-desktop-linux-v<version>.AppImage`
     * Example: For version 1.2.5, name the file `aniwings-desktop-linux-v1.2.5.AppImage`

3. **Version Resolution**:
   - The `<version>` tag is dynamically derived from the `version:` field in `pubspec.yaml` (taking the semver part before the `+`, e.g., `1.2.5` from `1.2.5+12`).

4. **Build Automation**:
   - Windows: Use `tool/build-release.ps1` to build and populate `./release/aniwings-desktop-windows-v<version>.exe`.
   - Linux: Use `tool/build-release.sh` to build and package `./release/aniwings-desktop-linux-v<version>.AppImage`.
