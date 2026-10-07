import 'dart:io';
import 'package:http/http.dart' as http;

/// Transfers verified media to a staging file. The caller publishes only after
/// this future succeeds; errors never leave an apparently complete download.
class MediaDownload {
  final http.Client client;
  final Future<void> Function(String url)? exportHls;
  MediaDownload(this.client, {this.exportHls});
  static const timeout = Duration(seconds: 30);

  Future<String> save({
    required String url,
    required File file,
    required Map<String, String> headers,
    required int maxHeight,
    required void Function(double) onProgress,
  }) async {
    IOSink? sink;
    try {
      var uri = Uri.parse(url);
      var response = await _open(uri, headers);
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (uri.path.endsWith('.m3u8') || type.contains('mpegurl')) {
        if (exportHls != null) {
          await response.stream.listen((_) {}).cancel();
          await exportHls!(url);
          if (!await file.exists() || await file.length() < 16) {
            throw const FormatException('HLS export did not produce a video');
          }
          final reader = await file.open();
          try {
            if (detectExtension(await reader.read(32)) != 'mp4') {
              throw const FormatException('HLS export produced invalid MP4');
            }
          } finally {
            await reader.close();
          }
          return 'mp4';
        }
        var body = await response.stream.bytesToString().timeout(timeout);
        for (var depth = 0; body.contains('#EXT-X-STREAM-INF'); depth++) {
          if (depth >= 3) {
            throw const FormatException('Nested HLS playlist limit');
          }
          if (RegExp(r'#EXT-X-MEDIA:.*TYPE=AUDIO.*URI=').hasMatch(body)) {
            throw const FormatException(
              'Separate HLS audio needs a muxer; trying another server',
            );
          }
          uri = selectVariant(body, uri, maxHeight);
          response = await _open(uri, headers);
          body = await response.stream.bytesToString().timeout(timeout);
        }
        if (!body.trimLeft().startsWith('#EXTM3U') ||
            !body.contains('#EXT-X-ENDLIST')) {
          throw const FormatException('Missing or unfinished HLS playlist');
        }
        if (RegExp(
          r'#EXT-X-KEY:(?!METHOD=NONE)|#EXT-X-BYTERANGE|#EXT-X-DISCONTINUITY\s',
          multiLine: true,
        ).hasMatch(body)) {
          throw const FormatException(
            'This HLS format cannot be saved safely; trying another server',
          );
        }
        if (!body.contains('#EXT-X-ENDLIST')) {
          throw const FormatException(
            'Live or incomplete HLS cannot be saved as an episode',
          );
        }
        final maps = RegExp(
          r'#EXT-X-MAP:URI="([^"]+)"',
        ).allMatches(body).toList();
        if (maps.length > 1 || body.contains('BYTERANGE=')) {
          throw const FormatException('Unsupported HLS initialization');
        }
        final segments = body
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .map(uri.resolve)
            .toList();
        if (segments.isEmpty || !body.contains('#EXTINF:')) {
          throw const FormatException('No HLS media segments');
        }
        final extension = maps.isEmpty ? 'ts' : 'mp4';
        if (maps.isNotEmpty) {
          segments.insert(0, uri.resolve(maps.single.group(1)!));
        }
        sink = file.openWrite();
        for (var i = 0; i < segments.length; i++) {
          final segment = await _open(segments[i], headers);
          final bytes = await segment.stream.toBytes().timeout(timeout);
          if (bytes.isEmpty ||
              (segment.contentLength != null &&
                  bytes.length != segment.contentLength)) {
            throw const FormatException('Incomplete HLS segment');
          }
          final invalidTs = extension == 'ts' && detectExtension(bytes) != 'ts';
          final invalidInit =
              extension == 'mp4' && i == 0 && detectExtension(bytes) != 'mp4';
          final invalidFragment =
              extension == 'mp4' &&
              i > 0 &&
              (bytes.length < 8 ||
                  !{
                    'styp',
                    'moof',
                    'sidx',
                    'emsg',
                  }.contains(String.fromCharCodes(bytes.sublist(4, 8))));
          if (invalidTs || invalidInit || invalidFragment) {
            throw const FormatException('HLS server returned invalid media');
          }
          sink.add(bytes);
          // Apply disk backpressure rather than accumulating an episode in RAM.
          await sink.flush();
          onProgress((i + 1) / segments.length);
        }
        await sink.close();
        sink = null;
        return extension;
      }
      if (type.contains('html') ||
          type.contains('json') ||
          type.startsWith('text/')) {
        throw const FormatException('Server returned a page instead of video');
      }
      sink = file.openWrite();
      var received = 0;
      final prefix = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        if (prefix.length < 512) prefix.addAll(chunk.take(512 - prefix.length));
        sink.add(chunk);
        received += chunk.length;
        await sink.flush();
        onProgress(
          response.contentLength != null && response.contentLength! > 0
              ? received / response.contentLength!
              : 0,
        );
      }
      final extension = detectExtension(prefix);
      if (received == 0 ||
          extension == null ||
          (response.contentLength != null &&
              received != response.contentLength)) {
        throw const FormatException('Invalid or incomplete video response');
      }
      await sink.close();
      sink = null;
      return extension;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {
        /* preserve transfer error */
      }
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<http.StreamedResponse> _open(
    Uri uri,
    Map<String, String> headers,
  ) async {
    if (!{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Invalid media URL');
    }
    final request = http.Request('GET', uri)..headers.addAll(headers);
    final response = await client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw HttpException('Media request failed (${response.statusCode})');
    }
    return response;
  }

  static String? detectExtension(List<int> bytes) {
    if (bytes.length >= 8 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      return 'mp4';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return 'mkv';
    }
    if (bytes.length >= 188 &&
        bytes[0] == 0x47 &&
        (bytes.length < 376 || bytes[188] == 0x47)) {
      return 'ts';
    }
    return null;
  }

  static Uri selectVariant(String body, Uri base, int maxHeight) {
    final lines = body.split('\n').map((s) => s.trim()).toList();
    final variants = <({Uri uri, int height, int bandwidth})>[];
    for (var i = 0; i < lines.length - 1; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
      final height =
          int.tryParse(
            RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i])?.group(1) ??
                '',
          ) ??
          0;
      final bandwidth =
          int.tryParse(
            RegExp(
                  r'(?:^|,)BANDWIDTH=(\d+)',
                ).firstMatch(lines[i].substring(18))?.group(1) ??
                '',
          ) ??
          0;
      final next = lines[i + 1];
      if (next.isEmpty || next.startsWith('#')) continue;
      variants.add((
        uri: base.resolve(next),
        height: height,
        bandwidth: bandwidth,
      ));
    }
    if (variants.isEmpty) throw const FormatException('No HLS variants');
    variants.sort(
      (a, b) => a.height == b.height
          ? b.bandwidth.compareTo(a.bandwidth)
          : b.height.compareTo(a.height),
    );
    return variants
        .firstWhere(
          (v) => maxHeight == 0 || v.height <= maxHeight,
          orElse: () => variants.last,
        )
        .uri;
  }
}
