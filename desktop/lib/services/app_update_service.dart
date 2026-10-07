import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;

import '../core/services/device_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

/// Shared notifier that manages background update checking and banner notifications for desktop.
final desktopUpdateAvailableProvider =
    StateNotifierProvider<DesktopUpdateNotifier, AppUpdateCheckResult?>((ref) {
      return DesktopUpdateNotifier(ref);
    });

class DesktopUpdateNotifier extends StateNotifier<AppUpdateCheckResult?> {
  final Ref _ref;
  bool _hasChecked = false;

  DesktopUpdateNotifier(this._ref) : super(null);

  Future<void> checkForUpdates() async {
    if (_hasChecked) return;
    _hasChecked = true;
    try {
      final result = await _ref.read(appUpdateServiceProvider).check();
      if (result.hasUpdate) {
        state = result;
      }
    } catch (_) {}
  }

  void dismiss() {
    state = null;
  }
}

class AppUpdateService {
  static const fallbackAppVersion = '1.2.5+12';
  static const pagesUpdateUrl = 'https://aniwings-app.pages.dev/update.json';
  static const githubReleasesLatestUrl =
      'https://api.github.com/repos/thehakaiben-cmyk/aniwings-app/releases/latest';

  final http.Client _client;
  final Future<String?> Function() _installedVersionProvider;

  AppUpdateService({
    http.Client? client,
    Future<String?> Function()? installedVersionProvider,
  }) : _client = client ?? http.Client(),
       _installedVersionProvider =
           installedVersionProvider ?? DeviceService.installedAppVersion;

  Uri updateUri() {
    if (kIsWeb) {
      return Uri.parse('${Uri.base.origin}/update.json');
    }
    return Uri.parse(pagesUpdateUrl);
  }

  /// Directly queries GitHub Releases API for the latest published release.
  Future<AppReleaseMetadata?> checkGitHubRelease({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final response = await _client
          .get(
            Uri.parse(githubReleasesLatestUrl),
            headers: const {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent': 'AniWings-Desktop-App',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return AppReleaseMetadata.fromGitHubJson(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<AppUpdateCheckResult> check({
    Uri? uri,
    Duration timeout = const Duration(seconds: 4),
    bool includeGitHubFallback = true,
  }) async {
    final currentVersion =
        await _installedVersionProvider() ?? fallbackAppVersion;
    final current = AppVersion.parse(currentVersion);

    AppReleaseMetadata? release;
    AppUpdateException? primaryError;

    try {
      final response = await _client.get(uri ?? updateUri()).timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          release = AppReleaseMetadata.fromJson(decoded);
        }
      } else {
        primaryError = AppUpdateException(
          'Update metadata returned ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is AppUpdateException) {
        primaryError = e;
      } else {
        primaryError = AppUpdateException('Failed to check update: $e');
      }
    }

    final shouldCheckGitHub = includeGitHubFallback && uri == null;
    if (shouldCheckGitHub) {
      final latestFromPages = release != null
          ? AppVersion.parse(release.version)
          : null;
      if (release == null || !current.isOlderThan(latestFromPages!)) {
        try {
          final gitHubRelease = await checkGitHubRelease(timeout: timeout);
          if (gitHubRelease != null) {
            final gitHubVersion = AppVersion.parse(gitHubRelease.version);
            if (latestFromPages == null ||
                gitHubVersion.compareTo(latestFromPages) > 0) {
              release = gitHubRelease;
              primaryError = null;
            }
          }
        } catch (_) {}
      }
    }

    if (release == null) {
      throw primaryError ?? AppUpdateException('Update metadata unavailable');
    }

    final latest = AppVersion.parse(release.version);
    final minimum = release.minVersion.trim().isEmpty
        ? null
        : AppVersion.parse(release.minVersion);

    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      release: release,
      hasUpdate: current.isOlderThan(latest),
      isMandatory:
          release.mandatory ||
          (minimum != null && current.isOlderThan(minimum)),
    );
  }

  static String displayVersion(String version) {
    var cleaned = version.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1).trim();
    }
    final semver = cleaned.split('+').first.trim();
    return semver.isEmpty ? cleaned : semver;
  }
}

class AppReleaseMetadata {
  final String version;
  final String minVersion;
  final String url;
  final String desktopUrl;
  final String windowsUrl;
  final String linuxUrl;
  final bool mandatory;
  final List<String> releaseNotes;
  final String releasedAt;
  final String fileSize;

  const AppReleaseMetadata({
    required this.version,
    required this.minVersion,
    required this.url,
    this.desktopUrl = '',
    this.windowsUrl = '',
    this.linuxUrl = '',
    required this.mandatory,
    required this.releaseNotes,
    required this.releasedAt,
    this.fileSize = '',
  });

  /// Extracts a semantic version string from release URLs or filenames, e.g.:
  /// - `.../releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe` -> `1.2.5`
  /// - `.../releases/download/v1.2.5/aniwings-desktop-linux-v1.2.5.AppImage` -> `1.2.5`
  /// - `aniwings-desktop-windows-v1.2.5.exe` -> `1.2.5`
  static String? extractVersionFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    // 1. Tag in GitHub release path: /releases/download/v?X.Y.Z(+B)?/
    final tagMatch = RegExp(
      r'/releases/download/v?([0-9]+(?:\.[0-9]+)+(?:\+[0-9]+)?)(?:/|$)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (tagMatch != null) {
      return tagMatch.group(1);
    }

    // 2. Binary filename format: aniwings-desktop-(windows|linux)-v?X.Y.Z
    final fileMatch = RegExp(
      r'aniwings-desktop-(?:windows|linux)-v?([0-9]+(?:\.[0-9]+)+(?:\+[0-9]+)?)\.',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (fileMatch != null) {
      return fileMatch.group(1);
    }

    // 3. Generic version suffix before file extension: -v?X.Y.Z.ext
    final genericMatch = RegExp(
      r'[-_]v?([0-9]+(?:\.[0-9]+)+(?:\+[0-9]+)?)\.[a-zA-Z0-9]+$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (genericMatch != null) {
      return genericMatch.group(1);
    }

    return null;
  }

  factory AppReleaseMetadata.fromJson(Map<String, dynamic> json) {
    final notes = json['releaseNotes'] ?? json['notes'] ?? const <dynamic>[];
    final desktopMap = json['desktop'] is Map<String, dynamic>
        ? json['desktop'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final rawWindowsUrl =
        (desktopMap['windowsUrl'] as String? ??
                json['windowsUrl'] as String? ??
                '')
            .trim();
    final rawLinuxUrl =
        (desktopMap['linuxUrl'] as String? ?? json['linuxUrl'] as String? ?? '')
            .trim();
    final rawDesktopUrl =
        (desktopMap['url'] as String? ?? json['desktopUrl'] as String? ?? '')
            .trim();
    final rawUrl = (json['url'] as String? ?? '').trim();

    // Determine the version:
    // 1. Explicit desktop version if present in desktop block or desktopVersion field
    // 2. Extracted from desktop release URLs (windowsUrl, linuxUrl, desktopUrl)
    // 3. Explicit root version (if root url is not an apk, or if no desktop-specific urls exist)
    // 4. Extracted from root url
    // 5. Fallback app version
    String resolvedVersion = '';
    final explicitDesktopVersion =
        (desktopMap['version'] as String? ??
                json['desktopVersion'] as String? ??
                '')
            .trim();

    if (explicitDesktopVersion.isNotEmpty) {
      resolvedVersion = explicitDesktopVersion;
    } else {
      final fromDesktopUrl =
          extractVersionFromUrl(rawWindowsUrl) ??
          extractVersionFromUrl(rawLinuxUrl) ??
          extractVersionFromUrl(rawDesktopUrl);
      if (fromDesktopUrl != null && fromDesktopUrl.isNotEmpty) {
        resolvedVersion = fromDesktopUrl;
      } else {
        final rootVersion = (json['version'] as String? ?? '').trim();
        if (rootVersion.isNotEmpty) {
          resolvedVersion = rootVersion;
        } else {
          resolvedVersion =
              extractVersionFromUrl(rawUrl) ??
              AppUpdateService.fallbackAppVersion;
        }
      }
    }

    if (resolvedVersion.startsWith('v') || resolvedVersion.startsWith('V')) {
      resolvedVersion = resolvedVersion.substring(1).trim();
    }

    return AppReleaseMetadata(
      version: resolvedVersion.isNotEmpty
          ? resolvedVersion
          : AppUpdateService.fallbackAppVersion,
      minVersion:
          (desktopMap['minVersion'] as String? ??
                  json['minVersion'] as String? ??
                  '')
              .trim(),
      url: rawUrl,
      desktopUrl: rawDesktopUrl,
      windowsUrl: rawWindowsUrl,
      linuxUrl: rawLinuxUrl,
      mandatory:
          (desktopMap['mandatory'] as bool?) ??
          (json['mandatory'] as bool? ?? false),
      releaseNotes: notes is List
          ? notes
                .map((note) => note.toString().trim())
                .where((note) => note.isNotEmpty)
                .toList(growable: false)
          : (desktopMap['releaseNotes'] is List
                ? (desktopMap['releaseNotes'] as List)
                      .map((note) => note.toString().trim())
                      .where((note) => note.isNotEmpty)
                      .toList(growable: false)
                : const <String>[]),
      releasedAt:
          (desktopMap['releasedAt'] as String? ??
                  json['releasedAt'] as String? ??
                  desktopMap['updatedAt'] as String? ??
                  json['updatedAt'] as String? ??
                  '')
              .trim(),
      fileSize:
          (desktopMap['fileSize'] as String? ??
                  json['fileSize'] as String? ??
                  '')
              .trim(),
    );
  }

  factory AppReleaseMetadata.fromGitHubJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    var version = tagName;
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1).trim();
    }
    final body = (json['body'] as String? ?? '').trim();
    final publishedAt =
        (json['published_at'] as String? ?? json['created_at'] as String? ?? '')
            .trim();
    final htmlUrl = (json['html_url'] as String? ?? '').trim();

    String windowsUrl = '';
    String linuxUrl = '';
    String fileSize = '';

    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final downloadUrl = (asset['browser_download_url'] as String? ?? '')
            .trim();
        final sizeBytes = asset['size'] as int?;

        if (name.endsWith('.exe')) {
          windowsUrl = downloadUrl;
          if (fileSize.isEmpty && sizeBytes != null) {
            fileSize = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        } else if (name.endsWith('.appimage') || name.endsWith('.deb')) {
          linuxUrl = downloadUrl;
          if (fileSize.isEmpty && sizeBytes != null) {
            fileSize = '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        }
      }
    }

    final releaseNotes = body.isNotEmpty
        ? body
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    final desktopUrl = windowsUrl.isNotEmpty
        ? windowsUrl
        : (linuxUrl.isNotEmpty ? linuxUrl : htmlUrl);

    return AppReleaseMetadata(
      version: version.isNotEmpty
          ? version
          : AppUpdateService.fallbackAppVersion,
      minVersion: '',
      url: htmlUrl,
      desktopUrl: desktopUrl,
      windowsUrl: windowsUrl,
      linuxUrl: linuxUrl,
      mandatory: false,
      releaseNotes: releaseNotes,
      releasedAt: publishedAt,
      fileSize: fileSize,
    );
  }

  String get preferredDesktopUrl {
    if (!kIsWeb) {
      if (Platform.isWindows && windowsUrl.isNotEmpty) return windowsUrl;
      if (Platform.isLinux && linuxUrl.isNotEmpty) return linuxUrl;
      if (Platform.isWindows && url.endsWith('.exe')) return url;
      if (Platform.isLinux &&
          (url.endsWith('.AppImage') || url.endsWith('.deb'))) {
        return url;
      }
    }
    if (windowsUrl.isNotEmpty) return windowsUrl;
    if (linuxUrl.isNotEmpty) return linuxUrl;
    if (desktopUrl.isNotEmpty) return desktopUrl;
    if (url.isNotEmpty && !url.endsWith('.apk')) return url;
    return 'https://github.com/thehakaiben-cmyk/aniwings-app/releases';
  }
}

class AppUpdateCheckResult {
  final String currentVersion;
  final AppReleaseMetadata release;
  final bool hasUpdate;
  final bool isMandatory;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.release,
    required this.hasUpdate,
    required this.isMandatory,
  });

  String get updateUrl => release.preferredDesktopUrl;
  String get desktopUpdateUrl => release.preferredDesktopUrl;
}

class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  factory AppVersion.parse(String versionStr) {
    try {
      var cleaned = versionStr.trim();
      if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
        cleaned = cleaned.substring(1).trim();
      }

      final parts = cleaned.split('+');
      final semverPart = parts[0];
      final buildPart = parts.length > 1 ? parts[1] : '0';

      final semverParts = semverPart
          .split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList();
      final major = semverParts.isNotEmpty ? semverParts[0] : 0;
      final minor = semverParts.length > 1 ? semverParts[1] : 0;
      final patch = semverParts.length > 2 ? semverParts[2] : 0;
      final build = int.tryParse(buildPart) ?? 0;

      return AppVersion(major, minor, patch, build);
    } catch (_) {
      return const AppVersion(0, 0, 0, 0);
    }
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (build > 0 && other.build > 0) {
      return build.compareTo(other.build);
    }
    return 0;
  }

  bool isOlderThan(AppVersion other) => compareTo(other) < 0;
  bool isSameOrNewerThan(AppVersion other) => compareTo(other) >= 0;
}

class AppUpdateException implements Exception {
  final String message;

  const AppUpdateException(this.message);

  @override
  String toString() => message;
}
