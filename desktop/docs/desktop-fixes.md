# Desktop fixes — 6 October 2026

## Implemented

- Neutral charcoal surfaces and system typography; no runtime font downloads.
- Stable settings focus geometry, conventional switches, persistent panel scrollbar,
  fixed-width selection indicators, and working card density on Home and Search.
- Removed appearance options that had empty callbacks.
- Search explicitly overrides all inherited input borders and fill, eliminating the
  nested input outline and conflicting backgrounds.
- Startup checks multiple independent HTTPS endpoints concurrently. One reachable
  server, including a 403 or 405 response, is sufficient; blocked Google DNS no
  longer blocks the app. Startup wordmark remains visible and logo has no circular glow.
- Player preserves a working automatic server as further providers resolve. User
  switching remains immediate and display preferences are restored from storage.
- AniSkip receives only a known MAL identifier, never an inferred catalog number.
  Automatic skip defaults to off; when enabled, it skips only natural playback
  across a verified boundary once per load. Seeking into an interval does not trigger
  a skip. The Show skip buttons setting now reaches the player.
- Native video backend added for Windows/Linux, retaining custom controls.
- Replaced zero-filled fake torrent files with libtorrent peer streaming, piece
  scheduling and seek-aware HTTP range support. Torrent indexing is separate from
  session startup; only the chosen torrent starts streaming. Sessions stop on switch,
  language change, episode change or exit; late session results are discarded.
- Native Windows fullscreen and display-awake channel added. Fixed a missing closing
  brace in the DPI resize handler that prevented the Windows runner from compiling.
- Desktop startup gate permits Windows/Linux and rejects phone, TV and browser runs.

## Cloudflare desktop login

Endpoint: `PUT /api/v2/desktop/manual-users/me` on the existing Worker.
Separate D1 table: `desktop_manual_users`. Firebase owns authentication; D1 stores
verified UID/email, username, verification status and server timestamps. No passwords
or tokens are stored. Pending metadata retries remain supported.

Worker source: `C:/AndroidStudioProjects/aniwings/cloudflare-worker/worker.mjs`.
Migration: `desktop-login-schema.sql`, also copied into this checkout's docs folder.
The additive table migration and Worker were deployed successfully. Remote schema
inspection confirmed the desktop table. Worker deployment version:
`3356d576-24bb-4faa-bdfe-c2c5998a3a55`.

Twelve backend tests passed, including desktop/TV isolation endpoints, authentication,
moderation, SQLite persistence and pairing. A real desktop account login and its first
D1 row still need an installed desktop build to verify end to end.

## Verification and limitations

All 61 targeted Flutter tests passed, and Flutter analysis reports no issues.
The targeted Flutter suites cover settings rendering/save behavior and density,
connectivity failures, login sync, timing boundaries, torrent source rules/scrapers,
player aspect-ratio stability, seek-safe skip behavior and navigation. The settings
preview is `test/goldens/desktop-settings.png`.

Windows release build currently stops because this machine lacks the Visual Studio
C++ toolchain. Flutter Windows support was enabled, but plugin setup also reported
that Windows Developer Mode is required for symlinks. No new desktop executable or
installer was produced. Native DLL loading, real peer transfer/seeking, fullscreen,
display-awake handling and live provider playback remain unverified in a Windows build.
The previous placeholder-torrent test was replaced with rejection of invalid inputs;
passing unit tests is not evidence of a successful real torrent download.

Catalog/CDN availability and provider response time remain external dependencies.
Missing poster artwork in the attached screenshots cannot be verified against a
native running build in this environment. Linux native window controls are not
implemented by the Windows runner. `libtorrent_flutter` carries GPL-3.0 licensing.


## Settings and watch dialog revision — 6 October 2026

Settings uses separate bordered preference rows, aligned label/control columns on wide windows, stacked controls on narrower windows, larger selection targets, and an automatic-save header. Native and embedded-player option dialogs use desktop close controls instead of drag handles. Watch dialogs now provide Material typography, a common header and bounded scrolling; short DNS/server lists size to their contents. DNS values match Settings, including migration of legacy Default to Off.

A persistent keyed player host retains player state when switching fullscreen or crossing the responsive layout breakpoint. Source changes still intentionally replace the source-keyed player. Regression checks assert identical player state, no additional platform video creation, and preserved position across mode/size changes; DNS checks cover compact surface height and persisted system resolver selection.


## Hover window caption — 6 October 2026

The Windows runner starts with its native caption hidden. A DPI-aware top-edge hover reveals standard minimize, maximize and close buttons; leaving the caption hides it after 700 ms. Window menus and dragging/resizing suspend hiding. Alt+Space still opens the native window menu. The timer is released on window destruction, and video fullscreen keeps its existing borderless behavior.

Native Windows verification requires the Visual Studio C++ toolchain, which is not installed on this host. The Android API 34 desktop emulator draws its caption in the system shell and ignored app-side caption visibility requests during device verification. The unsuccessful Android experiment was reverted; this Windows caption behavior cannot be previewed in that emulator.
