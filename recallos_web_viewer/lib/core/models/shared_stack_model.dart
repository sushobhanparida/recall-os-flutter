import 'dart:convert';

class SharedStack {
  final String id;
  final String name;
  final List<String> imageUrls;

  const SharedStack({
    required this.id,
    required this.name,
    required this.imageUrls,
  });

  factory SharedStack.fromMap(Map<String, dynamic> map) {
    final raw = map['image_urls'];
    final urls = raw is List
        ? List<String>.from(raw)
        : List<String>.from(jsonDecode(raw as String) as List);
    return SharedStack(
      id: map['id'] as String,
      name: map['stack_name'] as String,
      imageUrls: urls,
    );
  }
}
