# Release Build Rules

## Overview
When building the app for Windows or Linux release, follow the specified release directory and file naming conventions.

## Instructions
1. **Target Folder**:
   Always place release artifacts inside `./release/` relative to the repository root. Ensure the folder exists if it does not already.

2. **File Naming Pattern**:
   - **Windows**: `aniwings-desktop-windows-v<version>.exe`
     (e.g., `aniwings-desktop-windows-v1.2.5.exe`)
   - **Linux**: `aniwings-desktop-linux-v<version>.AppImage`
     (e.g., `aniwings-desktop-linux-v1.2.5.AppImage`)

3. **Version Source**:
   Extract `<version>` from `pubspec.yaml` (e.g. `version: 1.2.5+12` -> `1.2.5`).
