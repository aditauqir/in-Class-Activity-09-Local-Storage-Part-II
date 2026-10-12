class Folder {
  final int? id;
  final String name;
  final DateTime createdAt;
  final int cardCount;

  Folder({
    this.id,
    required this.name,
    required this.createdAt,
    this.cardCount = 0,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      cardCount: (map['card_count'] as num?)?.toInt() ?? 0,
    );
  }

  Folder copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    int? cardCount,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      cardCount: cardCount ?? this.cardCount,
    );
  }
}
