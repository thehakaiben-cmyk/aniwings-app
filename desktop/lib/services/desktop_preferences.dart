import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'storage_service.dart';

final desktopDensityProvider = NotifierProvider<DesktopDensity, String>(
  DesktopDensity.new,
);

class DesktopDensity extends Notifier<String> {
  @override
  String build() => ref.watch(storageServiceProvider).getCardSizePreference();

  Future<void> select(String value) async {
    await ref.read(storageServiceProvider).setCardSizePreference(value);
    state = value;
  }
}

double desktopCardScale(String density) => switch (density) {
  'compact' => 0.85,
  'spacious' => 1.2,
  _ => 1.0,
};
