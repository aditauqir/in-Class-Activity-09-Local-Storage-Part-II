class CardRecord {
  final int? id;
  final String title;
  final String suit;
  final String notes;
  final String? imageRef;
  final int folderId;

  CardRecord({
    this.id,
    required this.title,
    required this.suit,
    this.notes = '',
    this.imageRef,
    required this.folderId,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'title': title,
      'suit': suit,
      'notes': notes,
      'image_ref': imageRef,
      'folder_id': folderId,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory CardRecord.fromMap(Map<String, dynamic> map) {
    return CardRecord(
      id: map['id'] as int?,
      title: map['title'] as String,
      suit: map['suit'] as String,
      notes: (map['notes'] as String?) ?? '',
      imageRef: map['image_ref'] as String?,
      folderId: map['folder_id'] as int,
    );
  }

  CardRecord copyWith({
    int? id,
    String? title,
    String? suit,
    String? notes,
    String? imageRef,
    int? folderId,
  }) {
    return CardRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      suit: suit ?? this.suit,
      notes: notes ?? this.notes,
      imageRef: imageRef ?? this.imageRef,
      folderId: folderId ?? this.folderId,
    );
  }
}
