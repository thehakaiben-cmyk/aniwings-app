# Desktop-only plugin registration

Vendored from `libtorrent_flutter` 2.0.0 on pub.dev. The upstream source and GPL-3.0
license are retained. The local pubspec registers only Windows and Linux FFI
plugins; Android, iOS and macOS registrations are omitted.

This prevents Android preview builds from downloading or compiling the desktop
torrent engine. It does not change the native Windows/Linux torrent API. The app
already checks platform support before starting a torrent session.

Upstream: https://github.com/ayman708-UX/libtorrent_flutter
