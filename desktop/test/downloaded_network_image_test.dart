import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aniwings/services/image_download_cache.dart';
import 'package:aniwings/widgets/downloaded_network_image.dart';

void main() {
  testWidgets(
    'visible resize variants decode prefetched artwork without another request',
    (tester) async {
      final asset = await rootBundle.load('assets/images/logo.png');
      var requests = 0;
      final cache = ImageDownloadCache(
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(
            asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
            200,
          );
        }),
      );
      addTearDown(cache.dispose);
      const url = 'https://example.com/prefetched-logo.png';
      await cache.prefetch([url]);
      Future<ImageInfo> decode(int size) {
        final stream = ResizeImage(
          DownloadedNetworkImage(url, downloadCache: cache),
          width: size,
          height: size,
        ).resolve(ImageConfiguration.empty);
        final loaded = Completer<ImageInfo>();
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            stream.removeListener(listener);
            loaded.complete(info);
          },
          onError: (Object error, StackTrace? stack) {
            stream.removeListener(listener);
            loaded.completeError(error, stack);
          },
        );
        stream.addListener(listener);
        return loaded.future;
      }

      final small = await tester.runAsync(() => decode(32));
      final large = await tester.runAsync(() => decode(64));
      expect(small!.image.width, 32);
      expect(large!.image.width, 64);
      expect(requests, 1);
      small.dispose();
      large.dispose();
    },
  );
}
