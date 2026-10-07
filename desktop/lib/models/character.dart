class Character {
  final String name;
  final String role;
  final String imageUrl;

  Character({required this.name, required this.role, required this.imageUrl});

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'role': role, 'imageUrl': imageUrl};
  }
}
