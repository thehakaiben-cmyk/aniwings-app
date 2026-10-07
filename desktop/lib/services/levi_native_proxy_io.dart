import 'dart:io';
import 'desktop_torrent_engine.dart';

/// Native peer streaming for the supported desktop targets.
bool get supportsLeviNativeStreaming => Platform.isWindows || Platform.isLinux;

Future<String?> prepareLeviNativeStream(
  String torrentUrl, {
  int? episodeNumber,
}) async {
  if (!supportsLeviNativeStreaming || torrentUrl.isEmpty) return null;
  return DesktopTorrentEngine.instance.startStream(
    torrentUrl,
    episodeNumber: episodeNumber,
  );
}

Future<void> stopLeviNativeStream(String url) async {
  if (supportsLeviNativeStreaming) {
    await DesktopTorrentEngine.instance.stopStream(url);
  }
}
