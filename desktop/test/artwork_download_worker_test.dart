import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aniwings/services/artwork_download_worker.dart';

void main() {
  test(
    'background worker transfers artwork bytes and reports HTTP failures',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final worker = ArtworkDownloadWorker();
      addTearDown(() async {
        worker.dispose();
        await server.close(force: true);
      });
      server.listen((request) async {
        if (request.uri.path == '/bad') {
          request.response.statusCode = 503;
        } else {
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      });
      final origin = 'http://127.0.0.1:${server.port}';
      expect(await worker.load('$origin/art'), [1, 2, 3]);
      await expectLater(worker.load('$origin/bad'), throwsStateError);
      expect(await worker.load('$origin/retry'), [1, 2, 3]);
    },
  );
}
