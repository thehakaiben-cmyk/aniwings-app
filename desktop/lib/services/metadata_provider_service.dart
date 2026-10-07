import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_service.dart';

enum MetadataProvider { myAnimeList, aniList }

extension MetadataProviderLabel on MetadataProvider {
  String get label =>
      this == MetadataProvider.aniList ? 'AniList' : 'MyAnimeList';
}

final metadataProviderPreference =
    NotifierProvider<MetadataPreference, MetadataProvider>(
      MetadataPreference.new,
    );

class MetadataPreference extends Notifier<MetadataProvider> {
  @override
  MetadataProvider build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString('metadata_provider') == 'myAnimeList'
        ? MetadataProvider.myAnimeList
        : MetadataProvider.aniList;
  }

  Future<void> select(MetadataProvider provider) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString('metadata_provider', provider.name);
    state = provider;
  }
}
