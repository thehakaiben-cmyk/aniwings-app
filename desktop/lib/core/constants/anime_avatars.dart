import 'package:flutter/material.dart';

class AnimeAvatar {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final Color borderColor;

  const AnimeAvatar({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.borderColor,
  });
}

class AnimeAvatarRepository {
  static const List<Color> _ringColors = [
    Color(0xFFFF4081), // Pink
    Color(0xFF00E676), // Emerald Green
    Color(0xFFFFD600), // Gold Yellow
    Color(0xFF00E5FF), // Cyan
    Color(0xFFE53935), // Red
    Color(0xFFAB47BC), // Purple
    Color(0xFF29B6F6), // Light Blue
    Color(0xFF8D6E63), // Brown
    Color(0xFFFFFFFF), // White
    Color(0xFFFF9100), // Orange
  ];

  static const Map<String, List<Map<String, String>>> _rawCategories = {
    'AttackOnTitan': [
      {'name': 'Eren', 'url': 'assets/images/avatars/attackontitan_eren.png'},
      {
        'name': 'Mikasa',
        'url': 'assets/images/avatars/attackontitan_mikasa.png',
      },
      {'name': 'Levi', 'url': 'assets/images/avatars/attackontitan_levi.png'},
      {'name': 'Armin', 'url': 'assets/images/avatars/attackontitan_armin.png'},
      {'name': 'Annie', 'url': 'assets/images/avatars/attackontitan_annie.png'},
      {
        'name': 'Connie',
        'url': 'assets/images/avatars/attackontitan_connie.png',
      },
    ],
    'Berserk': [
      {'name': 'Guts', 'url': 'assets/images/avatars/berserk_guts.png'},
      {'name': 'Griffith', 'url': 'assets/images/avatars/berserk_griffith.png'},
      {'name': 'Casca', 'url': 'assets/images/avatars/berserk_casca.png'},
      {'name': 'Farnese', 'url': 'assets/images/avatars/berserk_farnese.png'},
      {'name': 'Zodd', 'url': 'assets/images/avatars/berserk_zodd.png'},
    ],
    'Bleach': [
      {'name': 'Ichigo', 'url': 'assets/images/avatars/bleach_ichigo.png'},
      {'name': 'Rukia', 'url': 'assets/images/avatars/bleach_rukia.png'},
      {'name': 'Aizen', 'url': 'assets/images/avatars/bleach_aizen.png'},
      {'name': 'Kenpachi', 'url': 'assets/images/avatars/bleach_kenpachi.png'},
      {
        'name': 'Hitsugaya',
        'url': 'assets/images/avatars/bleach_hitsugaya.png',
      },
      {
        'name': 'Ulquiorra',
        'url': 'assets/images/avatars/bleach_ulquiorra.png',
      },
    ],
    'ChainSaw': [
      {'name': 'Denji', 'url': 'assets/images/avatars/chainsaw_denji.png'},
      {'name': 'Makima', 'url': 'assets/images/avatars/chainsaw_makima.png'},
      {'name': 'Power', 'url': 'assets/images/avatars/chainsaw_power.png'},
      {'name': 'Aki', 'url': 'assets/images/avatars/chainsaw_aki.png'},
      {'name': 'Angel', 'url': 'assets/images/avatars/chainsaw_angel.png'},
    ],
    'DeathNote': [
      {'name': 'Light', 'url': 'assets/images/avatars/deathnote_light.png'},
      {'name': 'L', 'url': 'assets/images/avatars/deathnote_l.png'},
      {'name': 'Ryuk', 'url': 'assets/images/avatars/deathnote_ryuk.png'},
      {'name': 'Misa', 'url': 'assets/images/avatars/deathnote_misa.png'},
      {'name': 'Near', 'url': 'assets/images/avatars/deathnote_near.png'},
    ],
    'DemonSlayer': [
      {
        'name': 'Tanjiro',
        'url': 'assets/images/avatars/demonslayer_tanjiro.png',
      },
      {'name': 'Nezuko', 'url': 'assets/images/avatars/demonslayer_nezuko.png'},
      {
        'name': 'Zenitsu',
        'url': 'assets/images/avatars/demonslayer_zenitsu.png',
      },
      {
        'name': 'Inosuke',
        'url': 'assets/images/avatars/demonslayer_inosuke.png',
      },
      {'name': 'Muzan', 'url': 'assets/images/avatars/demonslayer_muzan.png'},
      {
        'name': 'Mitsuri',
        'url': 'assets/images/avatars/demonslayer_mitsuri.png',
      },
    ],
    'DragonBall': [
      {'name': 'Goku', 'url': 'assets/images/avatars/dragonball_goku.png'},
      {'name': 'Vegeta', 'url': 'assets/images/avatars/dragonball_vegeta.png'},
      {
        'name': 'Goku SSB',
        'url': 'assets/images/avatars/dragonball_goku_ssb.png',
      },
      {
        'name': 'Kid Goku',
        'url': 'assets/images/avatars/dragonball_kid_goku.png',
      },
      {'name': 'Broly', 'url': 'assets/images/avatars/dragonball_broly.png'},
    ],
    'Haikyu': [
      {'name': 'Hinata', 'url': 'assets/images/avatars/haikyu_hinata.png'},
      {'name': 'Kageyama', 'url': 'assets/images/avatars/haikyu_kageyama.png'},
      {'name': 'Bokuto', 'url': 'assets/images/avatars/haikyu_bokuto.png'},
      {'name': 'Tanaka', 'url': 'assets/images/avatars/haikyu_tanaka.png'},
      {'name': 'Tendou', 'url': 'assets/images/avatars/haikyu_tendou.png'},
    ],
    'JujutsuKaisen': [
      {'name': 'Gojo', 'url': 'assets/images/avatars/jujutsukaisen_gojo.png'},
      {
        'name': 'Sukuna',
        'url': 'assets/images/avatars/jujutsukaisen_sukuna.png',
      },
      {'name': 'Yuji', 'url': 'assets/images/avatars/jujutsukaisen_yuji.png'},
      {
        'name': 'Kenjaku',
        'url': 'assets/images/avatars/jujutsukaisen_kenjaku.png',
      },
      {'name': 'Panda', 'url': 'assets/images/avatars/jujutsukaisen_panda.png'},
      {'name': 'Todo', 'url': 'assets/images/avatars/jujutsukaisen_todo.png'},
    ],
    'Naruto': [
      {'name': 'Naruto', 'url': 'assets/images/avatars/naruto_naruto.png'},
      {'name': 'Sasuke', 'url': 'assets/images/avatars/naruto_sasuke.png'},
      {'name': 'Kakashi', 'url': 'assets/images/avatars/naruto_kakashi.png'},
      {'name': 'Itachi', 'url': 'assets/images/avatars/naruto_naruto.png'},
      {'name': 'Gaara', 'url': 'assets/images/avatars/naruto_gaara.png'},
      {'name': 'Sakura', 'url': 'assets/images/avatars/naruto_sakura.png'},
      {'name': 'Tsunade', 'url': 'assets/images/avatars/naruto_tsunade.png'},
    ],
    'OnePiece': [
      {'name': 'Luffy', 'url': 'assets/images/avatars/onepiece_luffy.png'},
      {'name': 'Zoro', 'url': 'assets/images/avatars/onepiece_zoro.png'},
      {'name': 'Nami', 'url': 'assets/images/avatars/onepiece_nami.png'},
      {'name': 'Robin', 'url': 'assets/images/avatars/onepiece_robin.png'},
      {'name': 'Chopper', 'url': 'assets/images/avatars/onepiece_chopper.png'},
      {
        'name': 'Shirahoshi',
        'url': 'assets/images/avatars/onepiece_shirahoshi.png',
      },
    ],
    'OnePunchMan': [
      {
        'name': 'Saitama',
        'url': 'assets/images/avatars/onepunchman_saitama.png',
      },
      {
        'name': 'Tatsumaki',
        'url': 'assets/images/avatars/onepunchman_tatsumaki.png',
      },
      {'name': 'Fubuki', 'url': 'assets/images/avatars/onepunchman_fubuki.png'},
      {
        'name': 'Silver Fang',
        'url': 'assets/images/avatars/onepunchman_silver_fang.png',
      },
      {
        'name': 'Watchdog Man',
        'url': 'assets/images/avatars/onepunchman_watchdog_man.png',
      },
    ],
    'SpyFamily': [
      {'name': 'Anya', 'url': 'assets/images/avatars/spyfamily_anya.png'},
      {'name': 'Loid', 'url': 'assets/images/avatars/spyfamily_loid.png'},
      {'name': 'Yor', 'url': 'assets/images/avatars/spyfamily_yor.png'},
      {'name': 'Bond', 'url': 'assets/images/avatars/spyfamily_bond.png'},
      {'name': 'Becky', 'url': 'assets/images/avatars/spyfamily_becky.png'},
    ],
  };

  static Map<String, List<AnimeAvatar>> getCategories() {
    final Map<String, List<AnimeAvatar>> result = {};
    int colorIdx = 0;

    _rawCategories.forEach((category, items) {
      result[category] = items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final color = _ringColors[(colorIdx + idx) % _ringColors.length];
        return AnimeAvatar(
          id: '${category.toLowerCase()}_$idx',
          name: item['name']!,
          category: category,
          imageUrl: item['url']!,
          borderColor: color,
        );
      }).toList();
      colorIdx += items.length;
    });

    return result;
  }
}
