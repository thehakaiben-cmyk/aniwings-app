class AnimeCollection {
  final String id;
  final String name;
  final String description;
  final List<String> animeIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customCoverUrl;

  const AnimeCollection({
    required this.id,
    required this.name,
    required this.description,
    required this.animeIds,
    required this.createdAt,
    required this.updatedAt,
    this.customCoverUrl,
  });

  AnimeCollection copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? animeIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? customCoverUrl,
  }) {
    return AnimeCollection(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      animeIds: animeIds ?? this.animeIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customCoverUrl: customCoverUrl ?? this.customCoverUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'animeIds': animeIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (customCoverUrl != null) 'customCoverUrl': customCoverUrl,
    };
  }

  factory AnimeCollection.fromJson(Map<String, dynamic> json) {
    return AnimeCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      animeIds: List<String>.from(json['animeIds'] as List? ?? const []),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      customCoverUrl: json['customCoverUrl'] as String?,
    );
  }
}
