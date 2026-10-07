# Desktop metadata provider selection

Open **Settings → Metadata Provider**, select **AniList** or **MyAnimeList**, then
click your choice. It is saved on this desktop and applies immediately to Home rows,
Browse and genre filters, Search, Details and descriptions, characters, related
titles, recommendations, schedule and episode information. AniList is the default
for desktops without a saved preference. MyAnimeList metadata is obtained through Jikan.

Catalog requests use the selected provider. AniList mode does not send fallback
metadata requests to Jikan, so a MAL/Jikan timeout cannot hold those pages up.
If the selected catalog is unavailable, cached/offline rows may remain; choose
the other provider in Settings to fetch from it. Video server selection remains
in Playback and is independent of the metadata choice.

## Identity and episode mapping

- MAL IDs remain the canonical app ID whenever the catalog supplies an `idMal`.
  Both `malId` and `aniListId` remain attached to the title for playback resolution.
- AniList-only titles use `ani:<id>`; their IDs are never interpreted as numeric
  MAL IDs. A details lookup queries the correct AniList ID namespace, not two
  competing titles that happen to share a number.
- Switching catalogs leaves collections and watch history in place. A title with
  no MAL mapping cannot be loaded from MAL; switch back to AniList for that title.
- MAL mode uses Jikan episode numbers and titles. AniList mode uses available
  streaming episode numbers, thumbnails and aired schedule data. Sparse or
  shuffled episode lists are joined by episode number, not list position.
- AniList does not provide complete per-episode titles for every show. Released
  episodes without such information use `Episode N`. Completed shows use the
  catalog's episode total; airing shows are limited to the released count supplied
  by airing/next-episode data. Planned future episodes are not filled as released.
- Numbered episode IDs stay `<anime-id>_ep_<episode-number>` so playback and history
  continue referring to the same episode across a provider change.

## Implementation

- `lib/services/metadata_provider_service.dart`: persisted choice and reactive
  Riverpod provider. The preference key is `metadata_provider`.
- `lib/services/anime_service.dart`: selected-source requests, canonical ID
  mapping, episode numbering, and namespaced caches. Replacing the service
  invalidates its dependent Home/Browse/Search/Details/episode providers.
- `lib/services/storage_service.dart`: separate detail cache entries per source;
  category and episode cache keys also contain the source name.
- `lib/features/home/home_screen.dart`: clears local detail futures after a
  source change, so Continue Watching does not retain the previous service.
- `lib/features/settings/desktop_settings_screen.dart`: keyboard-accessible source cards,
  selected indicator, and deterministic category Up/Down/Right navigation.
- `lib/features/details/details_screen.dart`: namespaced links for related
  AniList-only titles.

## Validation

`test/metadata_provider_test.dart` covers selected-only requests, provider and
cache switching, stored preference, identity collisions, completed and airing
episode lists, unavailable-source isolation, and keyboard Settings navigation.
Existing services, details layout, navigation and playback tests also pass.

On 2026-10-05 a live AniList query resolved MAL ID 52991 to AniList ID 154587
(Frieren) and returned 28 episodes. The Jikan request timed out in that probe.
Native desktop playback and every title's streaming-provider mapping are not verified
by this probe; use known completed and currently airing titles to confirm in a desktop build.

Reference: [AniList Media fields and cross-provider IDs](https://docs.anilist.co/reference/object/media).
