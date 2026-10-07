#!/usr/bin/env bash
# Build release script for Linux
# Produces: release/aniwings-desktop-linux-v<version>.AppImage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

# 1. Parse version from pubspec.yaml
VERSION=$(grep -E '^version:' pubspec.yaml | head -n1 | sed -E 's/version:\s*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "${VERSION}" ]; then
  echo "Error: Could not parse version from pubspec.yaml" >&2
  exit 1
fi

echo "AniWings Desktop Release Version: v${VERSION}"

# 2. Ensure release directory exists
RELEASE_DIR="${PROJECT_DIR}/release"
mkdir -p "${RELEASE_DIR}"

TARGET_APPIMAGE="${RELEASE_DIR}/aniwings-desktop-linux-v${VERSION}.AppImage"

# 3. Build Linux release
echo "Running: flutter build linux --release..."
flutter build linux --release

# 4. Check build output bundle
BUNDLE_DIR="${PROJECT_DIR}/build/linux/x64/release/bundle"
if [ ! -d "${BUNDLE_DIR}" ]; then
  echo "Error: Bundle directory not found at ${BUNDLE_DIR}" >&2
  exit 1
fi

# 5. Build or generate AppImage
if command -v appimagetool >/dev/null 2>&1; then
  echo "Packaging AppImage using appimagetool..."
  APP_DIR="${PROJECT_DIR}/build/linux/AppDir"
  rm -rf "${APP_DIR}"
  mkdir -p "${APP_DIR}/usr/bin" "${APP_DIR}/usr/lib" "${APP_DIR}/usr/share/icons/hicolor/256x256/apps"

  cp -r "${BUNDLE_DIR}/"* "${APP_DIR}/usr/bin/"
  cp "${PROJECT_DIR}/assets/images/logo.png" "${APP_DIR}/usr/share/icons/hicolor/256x256/apps/aniwings.png" 2>/dev/null || true
  cp "${PROJECT_DIR}/assets/images/logo.png" "${APP_DIR}/aniwings.png" 2>/dev/null || true

  cat <<EOF > "${APP_DIR}/aniwings.desktop"
[Desktop Entry]
Name=AniWings Desktop
Exec=aniwings
Icon=aniwings
Type=Application
Categories=AudioVideo;Player;
Terminal=false
EOF

  cat <<'EOF' > "${APP_DIR}/AppRun"
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/bin/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/aniwings" "$@"
EOF
  chmod +x "${APP_DIR}/AppRun"
  export ARCH="x86_64"
  if appimagetool --help 2>&1 | grep -q -- '--no-appstream'; then
    appimagetool --no-appstream "${APP_DIR}" "${TARGET_APPIMAGE}"
  else
    appimagetool "${APP_DIR}" "${TARGET_APPIMAGE}"
  fi
else
  echo "Error: appimagetool is required to produce a valid AppImage." >&2
  exit 1
fi

echo "Linux release artifact created: ${TARGET_APPIMAGE}"
