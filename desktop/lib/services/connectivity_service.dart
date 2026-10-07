import 'package:http/http.dart' as http;
import 'dart:async';

/// A blocked catalog or DNS provider is not evidence that the device is offline.
class ConnectivityService {
  final http.Client client;
  ConnectivityService(this.client);

  Future<bool> isOnline() async {
    final probes = [
      'https://www.cloudflare.com/cdn-cgi/trace',
      'https://www.microsoft.com/',
      'https://graphql.anilist.co/',
    ];
    // Start independently; return as soon as any endpoint responds.
    final reachable = Completer<bool>();
    var remaining = probes.length;
    for (final url in probes) {
      unawaited(() async {
        try {
          await client.head(Uri.parse(url)).timeout(const Duration(seconds: 5));
          if (!reachable.isCompleted) reachable.complete(true);
        } catch (_) {
          // Try every endpoint before reporting offline.
        } finally {
          remaining--;
          if (remaining == 0 && !reachable.isCompleted) {
            reachable.complete(false);
          }
        }
      }());
    }
    return reachable.future;
  }
}
