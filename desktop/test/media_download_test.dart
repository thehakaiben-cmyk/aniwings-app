import 'dart:io';
import 'package:aniwings/services/media_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  late File target;
  final mp4 = [0, 0, 0, 24, ...'ftypisom'.codeUnits, ...List.filled(32, 0)];
  final ts = List.generate(376, (i) => i % 188 == 0 ? 0x47 : 0);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('media-test-');
    target = File('${directory.path}/video.part');
  });
  tearDown(() async => directory.delete(recursive: true));
  Future<String> save(
    MockClient client, {
    String url = 'https://media.test/video',
  }) async {
    try {
      return await MediaDownload(client).save(
        url: url,
        file: target,
        headers: {'Referer': 'https://source.test/'},
        maxHeight: 720,
        onProgress: (_) {},
      );
    } finally {
      client.close();
    }
  }

  test('verified progressive video completes with matching content', () async {
    expect(
      await save(
        MockClient((request) async {
          expect(request.headers['Referer'], 'https://source.test/');
          return http.Response.bytes(mp4, 200);
        }),
      ),
      'mp4',
    );
    expect(await target.readAsBytes(), mp4);
  });
  for (final status in [403, 404, 500]) {
    test('HTTP $status is a failure and leaves no file', () async {
      await expectLater(
        save(MockClient((_) async => http.Response('', status))),
        throwsA(isA<HttpException>()),
      );
      expect(await target.exists(), false);
    });
  }
  test('HTML 200 cannot masquerade as downloaded video', () async {
    await expectLater(
      save(MockClient((_) async => http.Response('<html>blocked</html>', 200))),
      throwsFormatException,
    );
    expect(await target.exists(), false);
  });
  test(
    'HLS selects requested ceiling, resolves relative paths and saves TS honestly',
    () async {
      final seen = <String>[];
      expect(
        await save(
          MockClient((request) async {
            seen.add(request.url.path);
            return switch (request.url.path) {
              '/master.m3u8' => http.Response(
                '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=500,RESOLUTION=1920x1080\nhigh.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=200,RESOLUTION=1280x720\nlow/list.m3u8',
                200,
              ),
              '/low/list.m3u8' => http.Response(
                '#EXTM3U\n#EXTINF:5,\none.ts\n#EXTINF:5,\ntwo.ts\n#EXT-X-ENDLIST',
                200,
              ),
              _ => http.Response.bytes(ts, 200),
            };
          }),
          url: 'https://media.test/master.m3u8',
        ),
        'ts',
      );
      expect(seen, [
        '/master.m3u8',
        '/low/list.m3u8',
        '/low/one.ts',
        '/low/two.ts',
      ]);
      expect(await target.length(), ts.length * 2);
    },
  );
  test(
    'failed segment removes partial video instead of reporting success',
    () async {
      await expectLater(
        save(
          MockClient((request) async {
            if (request.url.path.endsWith('.m3u8')) {
              return http.Response(
                '#EXTM3U\n#EXTINF:5,\none.ts\n#EXTINF:5,\ntwo.ts\n#EXT-X-ENDLIST',
                200,
              );
            }
            return request.url.path.endsWith('one.ts')
                ? http.Response.bytes(ts, 200)
                : http.Response('Unavailable', 503);
          }),
          url: 'https://media.test/list.m3u8',
        ),
        throwsA(isA<HttpException>()),
      );
      expect(await target.exists(), false);
    },
  );
  for (final tag in [
    '#EXT-X-KEY:METHOD=AES-128,URI="key"',
    '#EXT-X-BYTERANGE:123@0',
  ]) {
    test('unsupported HLS cannot produce corrupt output: $tag', () async {
      await expectLater(
        save(
          MockClient(
            (_) async => http.Response(
              '#EXTM3U\n$tag\n#EXTINF:5,\na.ts\n#EXT-X-ENDLIST',
              200,
            ),
          ),
          url: 'https://media.test/list.m3u8',
        ),
        throwsFormatException,
      );
      expect(await target.exists(), false);
    });
  }
}
