import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../services/image_download_cache.dart';

/// Decoding remains lazy; the network download can finish during the intro.
@immutable
class DownloadedNetworkImage extends ImageProvider<DownloadedNetworkImage> {
  final String url;
  final ImageDownloadCache? downloadCache;
  const DownloadedNetworkImage(this.url, {this.downloadCache});

  @override
  Future<DownloadedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DownloadedNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decode(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    try {
      final bytes = await (downloadCache ?? ImageDownloadCache.shared).load(
        url,
      );
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // Failed requests should not poison Flutter's decoded image cache.
      (downloadCache ?? ImageDownloadCache.shared).evict(url);
      PaintingBinding.instance.imageCache.evict(this);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DownloadedNetworkImage &&
      other.url == url &&
      identical(other.downloadCache, downloadCache);
  @override
  int get hashCode => Object.hash(url, downloadCache);
}
