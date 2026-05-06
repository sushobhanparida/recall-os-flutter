import 'dart:convert';
import 'screenshot_model.dart';

class Stack {
  final int? id;
  final String name;
  final DateTime createdAt;
  final List<Screenshot> screenshots;
  final String? sharedId;
  final bool isReadOnly;
  final bool isPrivate;
  final String? ownerAvatarUrl;
  final String? ownerName;
  final List<String> memberAvatars;

  const Stack({
    this.id,
    required this.name,
    required this.createdAt,
    this.screenshots = const [],
    this.sharedId,
    this.isReadOnly = false,
    this.isPrivate = true,
    this.ownerAvatarUrl,
    this.ownerName,
    this.memberAvatars = const [],
  });

  Stack copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    List<Screenshot>? screenshots,
    String? sharedId,
    bool clearSharedId = false,
    bool? isReadOnly,
    bool? isPrivate,
    String? ownerAvatarUrl,
    bool clearOwnerAvatarUrl = false,
    String? ownerName,
    bool clearOwnerName = false,
    List<String>? memberAvatars,
  }) {
    return Stack(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      screenshots: screenshots ?? this.screenshots,
      sharedId: clearSharedId ? null : (sharedId ?? this.sharedId),
      isReadOnly: isReadOnly ?? this.isReadOnly,
      isPrivate: isPrivate ?? this.isPrivate,
      ownerAvatarUrl: clearOwnerAvatarUrl ? null : (ownerAvatarUrl ?? this.ownerAvatarUrl),
      ownerName: clearOwnerName ? null : (ownerName ?? this.ownerName),
      memberAvatars: memberAvatars ?? this.memberAvatars,
    );
  }

  Screenshot? get coverImage =>
      screenshots.isNotEmpty ? screenshots.first : null;

  bool get isShared => sharedId != null;
  bool get isPublic => !isPrivate;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'sharedId': sharedId,
        'isReadOnly': isReadOnly ? 1 : 0,
        'isPrivate': isPrivate ? 1 : 0,
        'ownerAvatarUrl': ownerAvatarUrl,
        'ownerName': ownerName,
        'memberAvatars': jsonEncode(memberAvatars),
      };

  factory Stack.fromMap(Map<String, dynamic> map,
      {List<Screenshot> screenshots = const []}) {
    List<String> parsedAvatars = const [];
    final rawAvatars = map['memberAvatars'];
    if (rawAvatars is String && rawAvatars.isNotEmpty) {
      try {
        parsedAvatars = List<String>.from(jsonDecode(rawAvatars) as List);
      } catch (_) {}
    }
    return Stack(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      screenshots: screenshots,
      sharedId: map['sharedId'] as String?,
      isReadOnly: (map['isReadOnly'] as int? ?? 0) == 1,
      isPrivate: (map['isPrivate'] as int? ?? 1) == 1,
      ownerAvatarUrl: map['ownerAvatarUrl'] as String?,
      ownerName: map['ownerName'] as String?,
      memberAvatars: parsedAvatars,
    );
  }
}
