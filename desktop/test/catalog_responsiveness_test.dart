import 'dart:async';
import 'dart:convert';
import 'package:aniwings/services/anime_service.dart';
import 'package:aniwings/services/metadata_provider_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> title(int id, double score) => {
  'mal_id': id,
  'title': 'Title $id',
  'score': score,
  'genres': [
    {'name': 'Fantasy'},
  ],
  'themes': [
    {'name': 'Isekai'},
    {'name': 'Historical'},
  ],
};

void main() {
  test(
    'MAL theme browsing retains matching titles and catalog trending order',
    () async {
      final service = AnimeService(
        metadataProvider: MetadataProvider.myAnimeList,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [title(1, 6), title(2, 9)],
            }),
            200,
          ),
        ),
      );
      final results = await service.queryAnime(
        query: '',
        genre: 'Isekai',
        sortBy: 'Trending',
      );
      expect(results.map((anime) => anime.id), ['1', '2']);
      expect(results.first.genres, contains('Historical'));
    },
  );

  test('slow catalog response does not block the next request start', () async {
    final firstResponse = Completer<http.Response>();
    final secondStarted = Completer<void>();
    var requests = 0;
    final service = AnimeService(
      metadataProvider: MetadataProvider.myAnimeList,
      client: MockClient((request) async {
        requests++;
        if (requests == 1) return firstResponse.future;
        secondStarted.complete();
        return http.Response(
          jsonEncode({
            'data': [title(2, 9)],
          }),
          200,
        );
      }),
    );
    final first = service.queryAnime(
      query: '',
      genre: 'Action',
      sortBy: 'Rating',
    );
    final second = service.queryAnime(
      query: '',
      genre: 'Fantasy',
      sortBy: 'Rating',
    );
    try {
      await secondStarted.future.timeout(const Duration(seconds: 2));
      expect(firstResponse.isCompleted, isFalse);
    } finally {
      firstResponse.complete(
        http.Response(
          jsonEncode({
            'data': [title(1, 6)],
          }),
          200,
        ),
      );
      await Future.wait([first, second]);
    }
  });
}
